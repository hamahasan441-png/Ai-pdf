package com.aidocassistant.app.pdfimport

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.io.InterruptedIOException
import java.io.RandomAccessFile
import kotlin.coroutines.coroutineContext
import kotlin.math.ceil
import kotlin.math.min
import kotlin.random.Random

/**
 * Fast parallel range download for the PDF racing engine, hardened with:
 *  - Per-segment RESUME: a failed/stalled segment restarts from the exact byte it
 *    reached (Range: from-end), not from zero.
 *  - RETRY with exponential backoff + jitter on transient errors (IO, timeouts,
 *    HTTP 408/429/5xx), applied per segment and on the single-stream path.
 *  - `If-Range` guard so a resource changing mid-download is detected, not corrupted.
 *
 * Resume here is in-memory (within a single acquire() call); cross-restart resume
 * lives in GenericFileDownloader/ResumeState for the general file importer.
 */
class DirectDownloadStrategy(
    override val startDelayMs: Long = 0L,
    private val maxSegments: Int = 8,
    private val minSegmentBytes: Long = 512 * 1024,
    private val parallelThresholdBytes: Long = 2 * 1024 * 1024,
    private val maxRetriesPerSegment: Int = 5,
    private val baseBackoffMs: Long = 300L,
    private val maxBackoffMs: Long = 6_000L,
) : AcquisitionStrategy {

    override val name: String = "DirectDownload"

    private data class Caps(
        val finalUrl: HttpUrl,
        val contentLength: Long?,
        val acceptsRanges: Boolean,
        val etag: String?,
        val lastModified: String?,
    )

    override suspend fun acquire(url: HttpUrl, ctx: AcquisitionContext): File {
        val caps = withRetry { probe(url, ctx) }
        val out = ctx.scratchFile("direct")
        try {
            val len = caps.contentLength
            if (caps.acceptsRanges && len != null && len > parallelThresholdBytes) {
                parallelDownload(caps, len, out, ctx)
                verifyIntegrity(out, len)
            } else {
                val total = singleDownload(caps, out, ctx)
                if (total != null) verifyIntegrity(out, total)
            }
            return out
        } catch (t: Throwable) {
            out.delete()
            throw t
        }
    }

    private suspend fun probe(url: HttpUrl, ctx: AcquisitionContext): Caps =
        withContext(Dispatchers.IO) {
            val req = Request.Builder()
                .url(url)
                .headers(headers(ctx))
                .header("Range", "bytes=0-0")
                .build()
            ctx.client.newCall(req).execute().use { resp ->
                throwIfRetryable(resp.code)
                val acceptsRanges = resp.code == 206 ||
                    resp.header("Accept-Ranges").equals("bytes", true)
                val total = parseContentRangeTotal(resp.header("Content-Range"))
                    ?: resp.header("Content-Length")?.toLongOrNull()
                        ?.takeIf { resp.code == 200 }
                Caps(
                    finalUrl = resp.request.url,
                    contentLength = total,
                    acceptsRanges = acceptsRanges,
                    etag = resp.header("ETag"),
                    lastModified = resp.header("Last-Modified"),
                )
            }
        }

    private suspend fun parallelDownload(
        caps: Caps, total: Long, out: File, ctx: AcquisitionContext,
    ) = coroutineScope {
        RandomAccessFile(out, "rw").use { raf -> raf.setLength(total) }
        val segCount = (total / minSegmentBytes)
            .coerceIn(1, maxSegments.toLong()).toInt()
        val segSize = ceil(total.toDouble() / segCount).toLong()
        val written = LongArray(segCount)

        (0 until segCount).map { i ->
            val start = i * segSize
            val end = min(start + segSize - 1, total - 1)
            async(Dispatchers.IO) {
                downloadSegmentResumable(caps, start, end, out, ctx) { local ->
                    written[i] = local
                    ctx.progress.update(written.sum(), total)
                }
            }
        }.awaitAll()
    }

    /** Downloads [start..end], resuming from the last written byte on transient failures. */
    private suspend fun downloadSegmentResumable(
        caps: Caps, start: Long, end: Long, out: File,
        ctx: AcquisitionContext, onWrite: (Long) -> Unit,
    ) {
        var writtenInSegment = 0L
        var attempt = 0
        while (true) {
            try {
                val from = start + writtenInSegment
                if (from > end) return
                fetchRange(caps, from, end, out, ctx) { chunk ->
                    writtenInSegment += chunk
                    onWrite(writtenInSegment)
                }
                return
            } catch (ce: CancellationException) {
                throw ce
            } catch (t: Throwable) {
                if (!isRetryable(t) || attempt >= maxRetriesPerSegment) throw t
                attempt++
                delay(backoff(attempt))
            }
        }
    }

    private suspend fun fetchRange(
        caps: Caps, from: Long, end: Long, out: File,
        ctx: AcquisitionContext, onChunk: (Int) -> Unit,
    ) = withContext(Dispatchers.IO) {
        val builder = Request.Builder()
            .url(caps.finalUrl)
            .headers(headers(ctx))
            .header("Range", "bytes=$from-$end")
        (caps.etag ?: caps.lastModified)?.let { builder.header("If-Range", it) }

        ctx.client.newCall(builder.build()).execute().use { resp ->
            throwIfRetryable(resp.code)
            check(resp.code == 206) { "server ignored Range (code=${resp.code})" }
            val body = resp.body ?: throw IOException("empty body")
            val buf = ByteArray(64 * 1024)
            var pos = from
            RandomAccessFile(out, "rw").use { raf ->
                body.byteStream().use { input ->
                    while (true) {
                        coroutineContext.ensureActive()
                        val n = input.read(buf)
                        if (n < 0) break
                        synchronized(raf) {
                            raf.seek(pos)
                            raf.write(buf, 0, n)
                        }
                        pos += n
                        onChunk(n)
                    }
                }
            }
        }
    }

    private suspend fun singleDownload(
        caps: Caps, out: File, ctx: AcquisitionContext,
    ): Long? {
        var attempt = 0
        while (true) {
            try {
                return withContext(Dispatchers.IO) {
                    val req = Request.Builder()
                        .url(caps.finalUrl)
                        .headers(headers(ctx))
                        .build()
                    ctx.client.newCall(req).execute().use { resp ->
                        throwIfRetryable(resp.code)
                        check(resp.isSuccessful) { "HTTP ${resp.code}" }
                        val body = resp.body ?: throw IOException("empty body")
                        val total = body.contentLength().takeIf { it > 0 }
                        out.outputStream().use { sink ->
                            val buf = ByteArray(128 * 1024)
                            var written = 0L
                            body.byteStream().use { input ->
                                while (true) {
                                    coroutineContext.ensureActive()
                                    val n = input.read(buf)
                                    if (n < 0) break
                                    sink.write(buf, 0, n)
                                    written += n
                                    ctx.progress.update(written, total ?: -1L)
                                }
                            }
                        }
                        total
                    }
                }
            } catch (ce: CancellationException) {
                throw ce
            } catch (t: Throwable) {
                if (!isRetryable(t) || attempt >= maxRetriesPerSegment) throw t
                attempt++
                RandomAccessFile(out, "rw").use { it.setLength(0) }
                delay(backoff(attempt))
            }
        }
    }

    private fun verifyIntegrity(out: File, expected: Long) {
        val actual = out.length()
        if (actual != expected) {
            throw IOException("size mismatch: got $actual bytes, expected $expected")
        }
    }

    private suspend fun <T> withRetry(block: suspend () -> T): T {
        var attempt = 0
        while (true) {
            try {
                return block()
            } catch (ce: CancellationException) {
                throw ce
            } catch (t: Throwable) {
                if (!isRetryable(t) || attempt >= maxRetriesPerSegment) throw t
                attempt++
                delay(backoff(attempt))
            }
        }
    }

    private fun backoff(attempt: Int): Long {
        val exp = baseBackoffMs * (1L shl (attempt - 1).coerceIn(0, 20))
        val capped = min(exp, maxBackoffMs)
        val jitter = Random.nextLong(0, capped / 2 + 1)
        return capped / 2 + jitter
    }

    private fun isRetryable(t: Throwable): Boolean = when (t) {
        is RetryableHttpException -> true
        is InterruptedIOException -> true
        is IOException -> true
        else -> false
    }

    private fun throwIfRetryable(code: Int) {
        if (code == 408 || code == 429 || code in 500..599) {
            throw RetryableHttpException(code)
        }
    }

    private class RetryableHttpException(code: Int) :
        IOException("retryable HTTP status $code")

    private fun headers(ctx: AcquisitionContext): Headers {
        val b = Headers.Builder()
        ctx.defaultHeaders.forEach { (k, v) -> b.add(k, v) }
        return b.build()
    }

    private fun parseContentRangeTotal(header: String?): Long? {
        val slash = header?.lastIndexOf('/') ?: return null
        if (slash < 0) return null
        return header.substring(slash + 1).trim().toLongOrNull()
    }
}

package com.aidocassistant.app.pdfimport

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.Request
import java.io.File
import java.io.RandomAccessFile
import kotlin.coroutines.coroutineContext
import kotlin.math.ceil
import kotlin.math.min

class DirectDownloadStrategy(
    override val startDelayMs: Long = 0L,
    private val maxSegments: Int = 8,
    private val minSegmentBytes: Long = 512 * 1024,
    private val parallelThresholdBytes: Long = 2 * 1024 * 1024,
) : AcquisitionStrategy {

    override val name: String = "DirectDownload"

    private data class Caps(
        val finalUrl: HttpUrl,
        val contentLength: Long?,
        val acceptsRanges: Boolean,
        val etag: String?,
    )

    override suspend fun acquire(url: HttpUrl, ctx: AcquisitionContext): File {
        val caps = probe(url, ctx)
        val out = ctx.scratchFile("direct")
        try {
            val len = caps.contentLength
            if (caps.acceptsRanges && len != null && len > parallelThresholdBytes) {
                parallelDownload(caps, len, out, ctx)
            } else {
                singleDownload(caps, out, ctx)
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
                downloadSegment(caps, start, end, out, ctx) { local ->
                    written[i] = local
                    ctx.progress.update(written.sum(), total)
                }
            }
        }.awaitAll()
    }

    private suspend fun downloadSegment(
        caps: Caps, start: Long, end: Long, out: File,
        ctx: AcquisitionContext, onWrite: (Long) -> Unit,
    ) {
        val builder = Request.Builder()
            .url(caps.finalUrl)
            .headers(headers(ctx))
            .header("Range", "bytes=$start-$end")
        caps.etag?.let { builder.header("If-Range", it) }

        ctx.client.newCall(builder.build()).execute().use { resp ->
            check(resp.code == 206) { "server ignored Range (code=${resp.code})" }
            val body = resp.body ?: error("empty body")
            val buf = ByteArray(64 * 1024)
            var pos = start
            var local = 0L
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
                        pos += n; local += n
                        onWrite(local)
                    }
                }
            }
        }
    }

    private suspend fun singleDownload(caps: Caps, out: File, ctx: AcquisitionContext) =
        withContext(Dispatchers.IO) {
            val req = Request.Builder()
                .url(caps.finalUrl)
                .headers(headers(ctx))
                .build()
            ctx.client.newCall(req).execute().use { resp ->
                check(resp.isSuccessful) { "HTTP ${resp.code}" }
                val body = resp.body ?: error("empty body")
                val total = body.contentLength()
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
                            ctx.progress.update(written, total)
                        }
                    }
                }
            }
        }

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

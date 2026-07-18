package com.aidocassistant.app.pdfimport

import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
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
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.io.InterruptedIOException
import java.io.RandomAccessFile
import java.net.URLDecoder
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.coroutineContext
import kotlin.math.min
import kotlin.random.Random

/**
 * Hardened downloader for ANY file type.
 *
 * Strength features:
 *  - Parallel HTTP range download with adaptive segment count.
 *  - Per-segment RESUME: a failed/stalled segment restarts from the exact byte it
 *    reached (Range: from-end) rather than from zero. `If-Range` guards against the
 *    resource changing mid-download.
 *  - RETRY with exponential backoff + jitter on transient errors (IO, timeouts,
 *    5xx, 408, 429) — per segment, so one flaky connection doesn't fail the job.
 *  - INTEGRITY check: verifies the final size matches the advertised Content-Length.
 *  - HTML fallback: if the URL is a page (not a file) that links to a real file,
 *    the first strong file link is followed automatically.
 *  - THROUGHPUT reporting for the UI.
 *
 * Only legitimate browser behavior is used — a plain authenticated GET with the
 * user's existing session cookies.
 */
class GenericFileDownloader(
    private val appContext: Context,
    private val client: OkHttpClient,
    private val maxSegments: Int = 8,
    private val minSegmentBytes: Long = 512 * 1024,
    private val parallelThresholdBytes: Long = 2 * 1024 * 1024,
    private val maxRetriesPerSegment: Int = 5,
    private val baseBackoffMs: Long = 300L,
    private val maxBackoffMs: Long = 6_000L,
) {

    data class DownloadedFile(
        val file: File,
        val fileName: String,
        val mimeType: String,
        val bytes: Long,
        val pageCount: Int?,        // non-null only for PDFs
        val elapsedMs: Long,
        val avgBytesPerSec: Long,
        val retries: Int,           // total retry attempts across all segments
        val resumedBytes: Long,     // bytes already on disk from a prior run
    )

    private data class Caps(
        val finalUrl: HttpUrl,
        val contentLength: Long?,
        val acceptsRanges: Boolean,
        val etag: String?,
        val lastModified: String?,
        val contentType: String?,
        val dispositionFilename: String?,
    )

    private val defaultHeaders = mapOf(
        "User-Agent" to AcquisitionContext.DEFAULT_USER_AGENT,
        "Accept" to "*/*",
    )

    private val retryCounter = AtomicLong(0)

    suspend fun download(
        rawUrl: String,
        workDir: File,
        progress: ProgressSink = ProgressSink.NOOP,
        followHtml: Boolean = true,
    ): DownloadedFile {
        val url = parseUrl(rawUrl)
            ?: throw IllegalArgumentException("invalid URL: $rawUrl")
        workDir.mkdirs()
        ResumeState.sweepStale(workDir)
        retryCounter.set(0)
        val started = System.currentTimeMillis()

        val caps = withRetry("probe") { probe(url) }

        // Range-capable + known size + large enough -> resumable parallel download.
        val resumable = caps.acceptsRanges && caps.contentLength != null &&
            caps.contentLength > parallelThresholdBytes

        val resume = if (resumable) ResumeState.forUrl(workDir, normalizedKey(url, caps)) else null
        val out = resume?.partFile ?: File.createTempFile("dl_", ".part", workDir)
        var resumedBytes = 0L

        try {
            if (resume != null) {
                resume.prepare(
                    total = caps.contentLength!!,
                    finalUrl = caps.finalUrl.toString(),
                    etag = caps.etag,
                    lastModified = caps.lastModified,
                    computeSegCount = { adaptiveSegmentCount(it) },
                )
                resumedBytes = resume.bytesCompleted()
                parallelDownload(caps, resume, progress)
                verifyIntegrity(out, caps.contentLength!!)
                resume.complete()
            } else {
                val total = singleDownload(caps, out, progress)
                if (total != null) verifyIntegrity(out, total)
            }

            val type = FileTypeDetector.detect(out, caps.contentType, caps.finalUrl.toString())

            // If we asked for a file but got a web page, try to follow a file link.
            if (followHtml && type.mimeType == "text/html") {
                val link = extractPrimaryFileLink(out, caps.finalUrl)
                if (link != null) {
                    resume?.discardOnDisk() ?: out.delete()
                    return download(link.toString(), workDir, progress, followHtml = false)
                }
            }

            val elapsed = (System.currentTimeMillis() - started).coerceAtLeast(1)
            val bytes = out.length()
            val fileName = resolveFileName(caps, type.extension)
            val pageCount = if (type.mimeType == "application/pdf") pdfPageCount(out) else null
            val freshBytes = (bytes - resumedBytes).coerceAtLeast(1)

            return DownloadedFile(
                file = out,
                fileName = fileName,
                mimeType = type.mimeType,
                bytes = bytes,
                pageCount = pageCount,
                elapsedMs = elapsed,
                // Speed reflects bytes actually transferred this run, not resumed ones.
                avgBytesPerSec = freshBytes * 1000 / elapsed,
                retries = retryCounter.get().toInt(),
                resumedBytes = resumedBytes,
            )
        } catch (ce: CancellationException) {
            // Paused/cancelled: KEEP part + meta so the next run resumes.
            resume?.persist(force = true)
            throw ce
        } catch (t: Throwable) {
            if (resume != null) {
                // Network error: keep files for a later resume; only clean non-resumable temp.
                resume.persist(force = true)
            } else {
                out.delete()
            }
            throw t
        }
    }

    /** Stable resume key: final URL + validator + length, so a changed resource keys differently. */
    private fun normalizedKey(url: HttpUrl, caps: Caps): String =
        "${caps.finalUrl}|${caps.etag ?: caps.lastModified ?: ""}|${caps.contentLength ?: -1}"

    // --- Probe ---

    private suspend fun probe(url: HttpUrl): Caps = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url(url)
            .headers(headers())
            .header("Range", "bytes=0-0")
            .build()
        client.newCall(req).execute().use { resp ->
            throwIfRetryable(resp.code)
            val acceptsRanges = resp.code == 206 ||
                resp.header("Accept-Ranges").equals("bytes", true)
            val total = parseContentRangeTotal(resp.header("Content-Range"))
                ?: resp.header("Content-Length")?.toLongOrNull()?.takeIf { resp.code == 200 }
            Caps(
                finalUrl = resp.request.url,
                contentLength = total,
                acceptsRanges = acceptsRanges,
                etag = resp.header("ETag"),
                lastModified = resp.header("Last-Modified"),
                contentType = resp.header("Content-Type"),
                dispositionFilename = parseDispositionFilename(resp.header("Content-Disposition")),
            )
        }
    }

    // --- Parallel range download with adaptive segmentation ---

    private suspend fun parallelDownload(
        caps: Caps, resume: ResumeState, progress: ProgressSink,
    ) = coroutineScope {
        val total = resume.contentLength
        val out = resume.partFile

        (0 until resume.segCount).map { i ->
            val segStart = resume.segStart(i)
            val segEnd = resume.segEnd(i)
            // Resume: skip the bytes this segment already completed on a prior run.
            val already = resume.written[i]
            async(Dispatchers.IO) {
                downloadSegmentResumable(caps, segStart + already, segEnd, out, already) { cumInSeg ->
                    resume.onSegmentProgress(i, cumInSeg)
                    progress.update(resume.bytesCompleted(), total)
                }
            }
        }.awaitAll()
    }

    private fun adaptiveSegmentCount(total: Long): Int =
        (total / minSegmentBytes).coerceIn(1, maxSegments.toLong()).toInt()

    /**
     * Downloads [start..end] into [out]. On a transient failure it resumes from the
     * byte it last wrote, retrying with exponential backoff. Uses If-Range so a
     * changed resource is detected instead of silently corrupting the file.
     */
    /**
     * Downloads absolute file range [startByte..end] into [out].
     * @param startByte first byte to fetch (already advanced past resumed bytes)
     * @param base bytes already completed in this segment before this call, used so
     *   [onWrite] always reports the cumulative-in-segment total (for persistence).
     * On a transient failure it resumes from the byte it last wrote and retries with
     * exponential backoff. `If-Range` detects a changed resource instead of corrupting.
     */
    private suspend fun downloadSegmentResumable(
        caps: Caps, startByte: Long, end: Long, out: File, base: Long, onWrite: (Long) -> Unit,
    ) {
        var writtenThisRun = 0L
        var attempt = 0
        while (true) {
            try {
                val from = startByte + writtenThisRun
                if (from > end) return
                fetchRange(caps, from, end, out) { chunk ->
                    writtenThisRun += chunk
                    onWrite(base + writtenThisRun)
                }
                return
            } catch (ce: CancellationException) {
                throw ce
            } catch (t: Throwable) {
                if (!isRetryable(t) || attempt >= maxRetriesPerSegment) throw t
                attempt++
                retryCounter.incrementAndGet()
                delay(backoff(attempt))
            }
        }
    }

    private suspend fun fetchRange(
        caps: Caps, from: Long, end: Long, out: File, onChunk: (Int) -> Unit,
    ) = withContext(Dispatchers.IO) {
        val builder = Request.Builder()
            .url(caps.finalUrl)
            .headers(headers())
            .header("Range", "bytes=$from-$end")
        // If-Range: only serve the range if the resource is unchanged.
        (caps.etag ?: caps.lastModified)?.let { builder.header("If-Range", it) }

        client.newCall(builder.build()).execute().use { resp ->
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

    // --- Single-connection download (unknown length / no range support) ---

    private suspend fun singleDownload(
        caps: Caps, out: File, progress: ProgressSink,
    ): Long? {
        var attempt = 0
        while (true) {
            try {
                return withContext(Dispatchers.IO) {
                    val req = Request.Builder().url(caps.finalUrl).headers(headers()).build()
                    client.newCall(req).execute().use { resp ->
                        throwIfRetryable(resp.code)
                        check(resp.isSuccessful) { "HTTP ${resp.code}" }
                        val body = resp.body ?: throw IOException("empty body")
                        val total = body.contentLength().takeIf { it > 0 }
                        out.outputStream().use { sink ->
                            val buf = ByteArray(128 * 1024)
                            var w = 0L
                            body.byteStream().use { input ->
                                while (true) {
                                    coroutineContext.ensureActive()
                                    val n = input.read(buf)
                                    if (n < 0) break
                                    sink.write(buf, 0, n)
                                    w += n
                                    progress.update(w, total ?: -1L)
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
                retryCounter.incrementAndGet()
                // Non-resumable path: restart from a clean file.
                RandomAccessFile(out, "rw").use { it.setLength(0) }
                delay(backoff(attempt))
            }
        }
    }

    // --- Integrity ---

    private fun verifyIntegrity(out: File, expected: Long) {
        val actual = out.length()
        if (actual != expected) {
            throw IOException("size mismatch: got $actual bytes, expected $expected")
        }
    }

    // --- HTML fallback: follow the first strong file link on a page ---

    private fun extractPrimaryFileLink(htmlFile: File, base: HttpUrl): HttpUrl? {
        val html = runCatching {
            htmlFile.inputStream().bufferedReader().use { it.readText().take(512 * 1024) }
        }.getOrNull() ?: return null

        val exts = "pdf|zip|rar|gz|7z|doc|docx|xls|xlsx|ppt|pptx|epub|mp3|mp4|" +
            "png|jpg|jpeg|gif|webp|csv|txt|apk"
        val regex = Regex(
            """(?:href|src|content)\s*=\s*["']([^"']+?\.(?:$exts)(?:\?[^"']*)?)["']""",
            RegexOption.IGNORE_CASE,
        )
        return regex.find(html)?.groupValues?.getOrNull(1)?.let { link ->
            base.resolve(link.replace("&amp;", "&").trim())
        }
    }

    // --- Retry helpers ---

    private suspend fun <T> withRetry(tag: String, block: suspend () -> T): T {
        var attempt = 0
        while (true) {
            try {
                return block()
            } catch (ce: CancellationException) {
                throw ce
            } catch (t: Throwable) {
                if (!isRetryable(t) || attempt >= maxRetriesPerSegment) throw t
                attempt++
                retryCounter.incrementAndGet()
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
        is InterruptedIOException -> true   // includes SocketTimeoutException
        is IOException -> true              // connection reset, EOF, etc.
        else -> false
    }

    private fun throwIfRetryable(code: Int) {
        if (code == 408 || code == 429 || code in 500..599) {
            throw RetryableHttpException(code)
        }
    }

    private class RetryableHttpException(val code: Int) :
        IOException("retryable HTTP status $code")

    // --- PDF / naming / parsing helpers ---

    private fun pdfPageCount(file: File): Int? = try {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
            val renderer = PdfRenderer(pfd)
            try {
                renderer.pageCount
            } finally {
                renderer.close()
            }
        }
    } catch (e: Exception) {
        null
    }

    private fun resolveFileName(caps: Caps, ext: String): String {
        caps.dispositionFilename?.let { return sanitize(ensureExt(it, ext)) }
        val path = caps.finalUrl.encodedPath
        val last = path.substringAfterLast('/', "")
        val decoded = if (last.isNotEmpty()) {
            runCatching { URLDecoder.decode(last, "UTF-8") }.getOrDefault(last)
        } else ""
        val base = when {
            decoded.isBlank() -> "download.$ext"
            decoded.contains('.') -> decoded
            else -> "$decoded.$ext"
        }
        return sanitize(base)
    }

    private fun ensureExt(name: String, ext: String): String =
        if (name.contains('.') || ext.isBlank()) name else "$name.$ext"

    private fun sanitize(name: String): String =
        name.replace(Regex("""[/\\:*?"<>|]"""), "_").take(120).ifBlank { "download" }

    private fun headers(): Headers {
        val b = Headers.Builder()
        defaultHeaders.forEach { (k, v) -> b.add(k, v) }
        return b.build()
    }

    private fun parseContentRangeTotal(header: String?): Long? {
        val slash = header?.lastIndexOf('/') ?: return null
        if (slash < 0) return null
        return header.substring(slash + 1).trim().toLongOrNull()
    }

    private fun parseDispositionFilename(header: String?): String? {
        if (header.isNullOrBlank()) return null
        Regex("""filename\*\s*=\s*[^']*''([^;]+)""", RegexOption.IGNORE_CASE)
            .find(header)?.groupValues?.getOrNull(1)?.let {
                return runCatching { URLDecoder.decode(it.trim(), "UTF-8") }.getOrDefault(it.trim())
            }
        Regex("""filename\s*=\s*"?([^";]+)"?""", RegexOption.IGNORE_CASE)
            .find(header)?.groupValues?.getOrNull(1)?.let { return it.trim() }
        return null
    }

    private fun parseUrl(raw: String): HttpUrl? {
        val trimmed = raw.trim()
        val withScheme = if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            trimmed
        } else {
            "https://$trimmed"
        }
        return withScheme.toHttpUrlOrNull()
    }
}

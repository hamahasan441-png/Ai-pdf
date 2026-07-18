package com.aidocassistant.app.pdfimport

import android.content.Context
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.RandomAccessFile
import java.net.URLDecoder
import kotlin.coroutines.coroutineContext
import kotlin.math.ceil
import kotlin.math.min

/**
 * Downloads ANY file from a URL (not just PDFs) as fast as possible, using a
 * parallel HTTP range download when the server supports it, and reports rich
 * metadata about what was downloaded (name, MIME type, size, page count if PDF).
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
) {

    data class DownloadedFile(
        val file: File,
        val fileName: String,
        val mimeType: String,
        val bytes: Long,
        val pageCount: Int?,   // non-null only for PDFs
        val elapsedMs: Long,
    )

    private data class Caps(
        val finalUrl: HttpUrl,
        val contentLength: Long?,
        val acceptsRanges: Boolean,
        val etag: String?,
        val contentType: String?,
        val dispositionFilename: String?,
    )

    private val defaultHeaders = mapOf(
        "User-Agent" to AcquisitionContext.DEFAULT_USER_AGENT,
        "Accept" to "*/*",
    )

    suspend fun download(
        rawUrl: String,
        workDir: File,
        progress: ProgressSink = ProgressSink.NOOP,
    ): DownloadedFile {
        val url = parseUrl(rawUrl)
            ?: throw IllegalArgumentException("invalid URL: $rawUrl")
        workDir.mkdirs()
        val started = System.currentTimeMillis()

        val caps = probe(url)
        val out = File.createTempFile("dl_", ".part", workDir)
        try {
            val len = caps.contentLength
            if (caps.acceptsRanges && len != null && len > parallelThresholdBytes) {
                parallelDownload(caps, len, out, progress)
            } else {
                singleDownload(caps, out, progress)
            }

            val type = FileTypeDetector.detect(out, caps.contentType, caps.finalUrl.toString())
            val fileName = resolveFileName(caps, type.extension)
            val pageCount = if (type.mimeType == "application/pdf") pdfPageCount(out) else null

            return DownloadedFile(
                file = out,
                fileName = fileName,
                mimeType = type.mimeType,
                bytes = out.length(),
                pageCount = pageCount,
                elapsedMs = System.currentTimeMillis() - started,
            )
        } catch (t: Throwable) {
            out.delete()
            throw t
        }
    }

    private suspend fun probe(url: HttpUrl): Caps = withContext(Dispatchers.IO) {
        val req = Request.Builder()
            .url(url)
            .headers(headers())
            .header("Range", "bytes=0-0")
            .build()
        client.newCall(req).execute().use { resp ->
            val acceptsRanges = resp.code == 206 ||
                resp.header("Accept-Ranges").equals("bytes", true)
            val total = parseContentRangeTotal(resp.header("Content-Range"))
                ?: resp.header("Content-Length")?.toLongOrNull()?.takeIf { resp.code == 200 }
            Caps(
                finalUrl = resp.request.url,
                contentLength = total,
                acceptsRanges = acceptsRanges,
                etag = resp.header("ETag"),
                contentType = resp.header("Content-Type"),
                dispositionFilename = parseDispositionFilename(resp.header("Content-Disposition")),
            )
        }
    }

    private suspend fun parallelDownload(
        caps: Caps, total: Long, out: File, progress: ProgressSink,
    ) = coroutineScope {
        RandomAccessFile(out, "rw").use { raf -> raf.setLength(total) }
        val segCount = (total / minSegmentBytes).coerceIn(1, maxSegments.toLong()).toInt()
        val segSize = ceil(total.toDouble() / segCount).toLong()
        val written = LongArray(segCount)

        (0 until segCount).map { i ->
            val start = i * segSize
            val end = min(start + segSize - 1, total - 1)
            async(Dispatchers.IO) {
                downloadSegment(caps, start, end, out) { local ->
                    written[i] = local
                    progress.update(written.sum(), total)
                }
            }
        }.awaitAll()
    }

    private suspend fun downloadSegment(
        caps: Caps, start: Long, end: Long, out: File, onWrite: (Long) -> Unit,
    ) {
        val builder = Request.Builder()
            .url(caps.finalUrl)
            .headers(headers())
            .header("Range", "bytes=$start-$end")
        caps.etag?.let { builder.header("If-Range", it) }

        client.newCall(builder.build()).execute().use { resp ->
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

    private suspend fun singleDownload(caps: Caps, out: File, progress: ProgressSink) =
        withContext(Dispatchers.IO) {
            val req = Request.Builder().url(caps.finalUrl).headers(headers()).build()
            client.newCall(req).execute().use { resp ->
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
                            progress.update(written, total)
                        }
                    }
                }
            }
        }

    private fun pdfPageCount(file: File): Int? = try {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
            PdfRenderer(pfd).use { it.pageCount }
        }
    } catch (_: Exception) {
        null
    }

    private fun resolveFileName(caps: Caps, ext: String): String {
        caps.dispositionFilename?.let { return sanitize(it) }
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
        // filename*=UTF-8''name.ext  (RFC 5987)
        Regex("""filename\*\s*=\s*[^']*''([^;]+)""", RegexOption.IGNORE_CASE)
            .find(header)?.groupValues?.getOrNull(1)?.let {
                return runCatching { URLDecoder.decode(it.trim(), "UTF-8") }.getOrDefault(it.trim())
            }
        // filename="name.ext"
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
        return try { HttpUrl.get(withScheme) } catch (_: IllegalArgumentException) { null }
    }
}

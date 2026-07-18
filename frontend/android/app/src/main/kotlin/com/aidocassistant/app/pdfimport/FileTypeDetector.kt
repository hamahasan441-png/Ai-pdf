package com.aidocassistant.app.pdfimport

import java.io.File
import java.io.RandomAccessFile
import java.util.Locale

/**
 * Detects the MIME type and a sensible file extension for a downloaded file,
 * using (in priority order): magic bytes, the server Content-Type, then the URL
 * extension. Works for any file type, not just PDFs.
 */
object FileTypeDetector {

    data class TypeInfo(val mimeType: String, val extension: String)

    private const val DEFAULT_MIME = "application/octet-stream"

    /** Best-effort detection combining bytes + server hints + url. */
    fun detect(file: File, serverContentType: String?, url: String): TypeInfo {
        // 1. Magic bytes are the most reliable.
        magicByteType(file)?.let { return it }

        // 2. Server Content-Type (strip charset/params).
        val ct = serverContentType?.substringBefore(';')?.trim()?.lowercase(Locale.ROOT)
        if (!ct.isNullOrEmpty() && ct != DEFAULT_MIME && ct != "application/force-download") {
            return TypeInfo(ct, extensionForMime(ct) ?: extFromUrl(url) ?: "bin")
        }

        // 3. URL extension.
        val urlExt = extFromUrl(url)
        if (urlExt != null) {
            return TypeInfo(mimeForExtension(urlExt) ?: DEFAULT_MIME, urlExt)
        }

        return TypeInfo(DEFAULT_MIME, "bin")
    }

    private fun magicByteType(file: File): TypeInfo? {
        if (!file.exists() || file.length() < 4L) return null
        val head = ByteArray(16)
        val read = RandomAccessFile(file, "r").use { raf ->
            val n = minOf(head.size.toLong(), raf.length()).toInt()
            raf.readFully(head, 0, n)
            n
        }
        fun startsWith(vararg bytes: Int): Boolean {
            if (read < bytes.size) return false
            return bytes.withIndex().all { (i, b) -> head[i].toInt() and 0xFF == b }
        }

        return when {
            startsWith(0x25, 0x50, 0x44, 0x46) -> TypeInfo("application/pdf", "pdf") // %PDF
            startsWith(0x89, 0x50, 0x4E, 0x47) -> TypeInfo("image/png", "png")
            startsWith(0xFF, 0xD8, 0xFF) -> TypeInfo("image/jpeg", "jpg")
            startsWith(0x47, 0x49, 0x46, 0x38) -> TypeInfo("image/gif", "gif")
            startsWith(0x42, 0x4D) -> TypeInfo("image/bmp", "bmp")
            isWebp(head, read) -> TypeInfo("image/webp", "webp")
            isMp4(head, read) -> TypeInfo("video/mp4", "mp4")
            startsWith(0x49, 0x44, 0x33) -> TypeInfo("audio/mpeg", "mp3") // ID3
            startsWith(0xFF, 0xFB) -> TypeInfo("audio/mpeg", "mp3")
            startsWith(0x4F, 0x67, 0x67, 0x53) -> TypeInfo("audio/ogg", "ogg") // OggS
            startsWith(0x1F, 0x8B) -> TypeInfo("application/gzip", "gz")
            startsWith(0x50, 0x4B, 0x03, 0x04) -> TypeInfo("application/zip", "zip") // may be docx/xlsx/epub
            startsWith(0x52, 0x61, 0x72, 0x21) -> TypeInfo("application/vnd.rar", "rar") // Rar!
            startsWith(0x7B, 0x5C, 0x72, 0x74) -> TypeInfo("application/rtf", "rtf") // {\rt
            isHtml(head, read) -> TypeInfo("text/html", "html")
            else -> null
        }
    }

    private fun isWebp(h: ByteArray, n: Int): Boolean =
        n >= 12 && h[0].toInt() == 0x52 && h[1].toInt() == 0x49 &&
            h[2].toInt() == 0x46 && h[3].toInt() == 0x46 &&
            h[8].toInt() == 0x57 && h[9].toInt() == 0x45 &&
            h[10].toInt() == 0x42 && h[11].toInt() == 0x50 // RIFF....WEBP

    private fun isMp4(h: ByteArray, n: Int): Boolean =
        n >= 8 && h[4].toInt() == 0x66 && h[5].toInt() == 0x74 &&
            h[6].toInt() == 0x79 && h[7].toInt() == 0x70 // ....ftyp

    private fun isHtml(h: ByteArray, n: Int): Boolean {
        val prefix = String(h, 0, n, Charsets.US_ASCII).trimStart().lowercase(Locale.ROOT)
        return prefix.startsWith("<!doctype html") || prefix.startsWith("<html")
    }

    private fun extFromUrl(url: String): String? {
        val path = url.substringBefore('?').substringBefore('#')
        val name = path.substringAfterLast('/', "")
        val ext = name.substringAfterLast('.', "")
        return if (ext.isNotEmpty() && ext.length <= 5) ext.lowercase(Locale.ROOT) else null
    }

    private fun extensionForMime(mime: String): String? = when (mime) {
        "application/pdf" -> "pdf"
        "image/png" -> "png"
        "image/jpeg" -> "jpg"
        "image/gif" -> "gif"
        "image/webp" -> "webp"
        "image/bmp" -> "bmp"
        "text/plain" -> "txt"
        "text/html" -> "html"
        "text/csv" -> "csv"
        "application/json" -> "json"
        "application/zip" -> "zip"
        "application/msword" -> "doc"
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> "docx"
        "application/vnd.ms-excel" -> "xls"
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> "xlsx"
        "application/vnd.ms-powerpoint" -> "ppt"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation" -> "pptx"
        "application/epub+zip" -> "epub"
        "audio/mpeg" -> "mp3"
        "audio/ogg" -> "ogg"
        "video/mp4" -> "mp4"
        else -> null
    }

    private fun mimeForExtension(ext: String): String? = when (ext) {
        "pdf" -> "application/pdf"
        "png" -> "image/png"
        "jpg", "jpeg" -> "image/jpeg"
        "gif" -> "image/gif"
        "webp" -> "image/webp"
        "bmp" -> "image/bmp"
        "txt" -> "text/plain"
        "html", "htm" -> "text/html"
        "csv" -> "text/csv"
        "json" -> "application/json"
        "zip" -> "application/zip"
        "doc" -> "application/msword"
        "docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        "xls" -> "application/vnd.ms-excel"
        "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        "ppt" -> "application/vnd.ms-powerpoint"
        "pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "epub" -> "application/epub+zip"
        "mp3" -> "audio/mpeg"
        "ogg" -> "audio/ogg"
        "mp4" -> "video/mp4"
        else -> null
    }
}

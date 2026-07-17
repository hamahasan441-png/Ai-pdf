package com.aidocassistant.app.pdfimport

import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile

object PdfValidator {

    sealed interface Verdict {
        data class Valid(val pageCount: Int) : Verdict
        data object NotPdf : Verdict
        data object Truncated : Verdict
        data object Encrypted : Verdict
        data class Corrupt(val message: String) : Verdict
    }

    private val PDF_MAGIC = "%PDF-".toByteArray(Charsets.US_ASCII)
    private val EOF_MARKER = "%%EOF".toByteArray(Charsets.US_ASCII)

    suspend fun verify(file: File): Verdict = withContext(Dispatchers.IO) {
        if (!file.exists() || file.length() < 32L) return@withContext Verdict.NotPdf
        if (!hasMagicNear(file, 1024)) return@withContext Verdict.NotPdf
        if (!hasEofNear(file, 2048)) return@withContext Verdict.Truncated

        try {
            ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { pfd ->
                PdfRenderer(pfd).use { renderer ->
                    Verdict.Valid(renderer.pageCount)
                }
            }
        } catch (e: SecurityException) {
            Verdict.Encrypted
        } catch (e: IOException) {
            Verdict.Corrupt(e.message ?: "unreadable PDF")
        } catch (e: Exception) {
            Verdict.Corrupt(e.message ?: e.javaClass.simpleName)
        }
    }

    private fun hasMagicNear(file: File, window: Int): Boolean =
        RandomAccessFile(file, "r").use { raf ->
            val len = minOf(window.toLong(), raf.length()).toInt()
            val head = ByteArray(len)
            raf.readFully(head)
            indexOf(head, PDF_MAGIC) >= 0
        }

    private fun hasEofNear(file: File, window: Int): Boolean =
        RandomAccessFile(file, "r").use { raf ->
            val len = minOf(window.toLong(), raf.length()).toInt()
            raf.seek(raf.length() - len)
            val tail = ByteArray(len)
            raf.readFully(tail)
            indexOf(tail, EOF_MARKER) >= 0
        }

    private fun indexOf(haystack: ByteArray, needle: ByteArray): Int {
        if (needle.isEmpty() || haystack.size < needle.size) return -1
        outer@ for (i in 0..haystack.size - needle.size) {
            for (j in needle.indices) {
                if (haystack[i + j] != needle[j]) continue@outer
            }
            return i
        }
        return -1
    }
}

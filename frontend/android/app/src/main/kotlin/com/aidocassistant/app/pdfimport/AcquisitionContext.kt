package com.aidocassistant.app.pdfimport

import android.content.Context
import okhttp3.OkHttpClient
import java.io.File

class AcquisitionContext(
    val appContext: Context,
    val client: OkHttpClient,
    val workDir: File,
    val progress: ProgressSink = ProgressSink.NOOP,
    val defaultHeaders: Map<String, String> = mapOf(
        "User-Agent" to DEFAULT_USER_AGENT,
        "Accept" to "application/pdf,*/*;q=0.9",
    ),
) {
    fun scratchFile(tag: String): File =
        File.createTempFile("pdf_${tag}_", ".part", workDir)

    companion object {
        const val DEFAULT_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/125.0 Mobile Safari/537.36"
    }
}

fun interface ProgressSink {
    fun update(bytesWritten: Long, totalBytes: Long)

    companion object {
        val NOOP = ProgressSink { _, _ -> }
    }
}

package com.aidocassistant.app.pdfimport

import okhttp3.HttpUrl
import java.io.File

interface AcquisitionStrategy {
    val name: String
    val startDelayMs: Long
    suspend fun acquire(url: HttpUrl, ctx: AcquisitionContext): File
}

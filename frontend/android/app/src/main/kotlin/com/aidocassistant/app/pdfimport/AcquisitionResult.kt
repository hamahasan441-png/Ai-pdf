package com.aidocassistant.app.pdfimport

import java.io.File

sealed interface AcquisitionResult {
    data class Success(
        val file: File,
        val strategyName: String,
        val pageCount: Int,
        val bytes: Long,
        val elapsedMs: Long,
    ) : AcquisitionResult

    data class Failure(
        val strategyName: String,
        val reason: String,
        val cause: Throwable? = null,
    ) : AcquisitionResult

    data class AllFailed(
        val failures: List<Failure>,
    ) : AcquisitionResult

    data class NoPdfAvailable(
        val reason: String,
    ) : AcquisitionResult
}

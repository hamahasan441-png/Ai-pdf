package com.aidocassistant.app.pdfimport

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.io.File

/**
 * Flutter platform channel bridge for the PDF import engine.
 *
 * MethodChannel: "com.aidocassistant.app/pdf_import"
 *   - importPdf(url: String): returns Map with result details
 *   - cancelImport(): cancels any in-progress import
 *
 * EventChannel: "com.aidocassistant.app/pdf_import_progress"
 *   - Streams progress events as Map {bytesWritten, totalBytes}
 */
class PdfImportPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private var engine: PdfImportEngine? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var currentJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        engine = PdfImportEngine.create(context)

        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_METHOD)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, CHANNEL_EVENT)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        currentJob?.cancel()
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "importPdf" -> handleImport(call, result)
            "cancelImport" -> handleCancel(result)
            else -> result.notImplemented()
        }
    }

    private fun handleImport(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("INVALID_URL", "URL is required", null)
            return
        }

        currentJob?.cancel()
        currentJob = scope.launch {
            val dest = File(context.cacheDir, "pdf_import/imported_${System.currentTimeMillis()}.pdf")
            val progress = ProgressSink { written, total ->
                scope.launch(Dispatchers.Main) {
                    eventSink?.success(mapOf("bytesWritten" to written, "totalBytes" to total))
                }
            }

            when (val outcome = engine!!.import(url, dest, progress)) {
                is AcquisitionResult.Success -> {
                    result.success(mapOf(
                        "status" to "success",
                        "filePath" to outcome.file.absolutePath,
                        "strategy" to outcome.strategyName,
                        "pageCount" to outcome.pageCount,
                        "bytes" to outcome.bytes,
                        "elapsedMs" to outcome.elapsedMs,
                    ))
                }
                is AcquisitionResult.NoPdfAvailable -> {
                    result.success(mapOf(
                        "status" to "unavailable",
                        "reason" to outcome.reason,
                    ))
                }
                is AcquisitionResult.AllFailed -> {
                    val reasons = outcome.failures.joinToString("; ") {
                        "${it.strategyName}: ${it.reason}"
                    }
                    result.success(mapOf(
                        "status" to "failed",
                        "reason" to reasons,
                    ))
                }
                else -> {
                    result.success(mapOf("status" to "failed", "reason" to "unknown"))
                }
            }
        }
    }

    private fun handleCancel(result: MethodChannel.Result) {
        currentJob?.cancel()
        currentJob = null
        result.success(null)
    }

    companion object {
        private const val CHANNEL_METHOD = "com.aidocassistant.app/pdf_import"
        private const val CHANNEL_EVENT = "com.aidocassistant.app/pdf_import_progress"
    }
}

package com.aidocassistant.app.pdfimport

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.ConnectionPool
import okhttp3.OkHttpClient
import okhttp3.Protocol
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Flutter platform channel bridge.
 *
 * MethodChannel: "com.aidocassistant.app/pdf_import"
 *   - importPdf(url)          -> race 5 strategies for a verified PDF
 *   - importFile(url)         -> download ANY file, return name/type/size/pages
 *   - saveFile(path,name,mime)-> open the system "Save as" dialog and write there
 *   - cancelImport()          -> cancel the in-progress download
 *
 * EventChannel: "com.aidocassistant.app/pdf_import_progress"
 *   - streams {bytesWritten, totalBytes}
 */
class PdfImportPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context

    private var engine: PdfImportEngine? = null
    private var downloader: GenericFileDownloader? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var currentJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null

    private var activity: Activity? = null

    // Pending "Save as" request awaiting the SAF activity result.
    private var pendingSaveResult: MethodChannel.Result? = null
    private var pendingSaveSourcePath: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        val client = buildClient()
        engine = PdfImportEngine.create(context)
        downloader = GenericFileDownloader(context, client)

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

    // --- ActivityAware (needed for the SAF "Save as" dialog) ---

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // --- Method dispatch ---

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "importPdf" -> handleImportPdf(call, result)
            "importFile" -> handleImportFile(call, result)
            "saveFile" -> handleSaveFile(call, result)
            "cancelImport" -> handleCancel(result)
            else -> result.notImplemented()
        }
    }

    private fun progressSink() = ProgressSink { written, total ->
        scope.launch(Dispatchers.Main) {
            eventSink?.success(mapOf("bytesWritten" to written, "totalBytes" to total))
        }
    }

    private fun handleImportPdf(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("INVALID_URL", "URL is required", null)
            return
        }
        currentJob?.cancel()
        currentJob = scope.launch {
            val dest = File(context.cacheDir, "pdf_import/imported_${System.currentTimeMillis()}.pdf")
            when (val outcome = engine!!.import(url, dest, progressSink())) {
                is AcquisitionResult.Success -> result.success(mapOf(
                    "status" to "success",
                    "filePath" to outcome.file.absolutePath,
                    "fileName" to outcome.file.name,
                    "mimeType" to "application/pdf",
                    "strategy" to outcome.strategyName,
                    "pageCount" to outcome.pageCount,
                    "bytes" to outcome.bytes,
                    "elapsedMs" to outcome.elapsedMs,
                ))
                is AcquisitionResult.NoPdfAvailable -> result.success(mapOf(
                    "status" to "unavailable", "reason" to outcome.reason,
                ))
                is AcquisitionResult.AllFailed -> result.success(mapOf(
                    "status" to "failed",
                    "reason" to outcome.failures.joinToString("; ") { "${it.strategyName}: ${it.reason}" },
                ))
                else -> result.success(mapOf("status" to "failed", "reason" to "unknown"))
            }
        }
    }

    private fun handleImportFile(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        if (url.isNullOrBlank()) {
            result.error("INVALID_URL", "URL is required", null)
            return
        }
        currentJob?.cancel()
        currentJob = scope.launch {
            try {
                val workDir = File(context.cacheDir, "file_import")
                val dl = downloader!!.download(url, workDir, progressSink())
                result.success(mapOf(
                    "status" to "success",
                    "filePath" to dl.file.absolutePath,
                    "fileName" to dl.fileName,
                    "mimeType" to dl.mimeType,
                    "bytes" to dl.bytes,
                    "pageCount" to dl.pageCount,
                    "elapsedMs" to dl.elapsedMs,
                    "avgBytesPerSec" to dl.avgBytesPerSec,
                    "retries" to dl.retries,
                ))
            } catch (ce: kotlinx.coroutines.CancellationException) {
                throw ce
            } catch (t: Throwable) {
                result.success(mapOf(
                    "status" to "failed",
                    "reason" to (t.message ?: t.javaClass.simpleName),
                ))
            }
        }
    }

    /** Opens the system Save-as dialog (SAF) and writes the file to the chosen location. */
    private fun handleSaveFile(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName") ?: "download"
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        val act = activity

        if (sourcePath.isNullOrBlank() || !File(sourcePath).exists()) {
            result.error("NO_SOURCE", "source file not found", null)
            return
        }
        if (act == null) {
            result.error("NO_ACTIVITY", "no foreground activity for save dialog", null)
            return
        }
        if (pendingSaveResult != null) {
            result.error("BUSY", "another save is in progress", null)
            return
        }

        pendingSaveResult = result
        pendingSaveSourcePath = sourcePath
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, fileName)
        }
        try {
            act.startActivityForResult(intent, REQ_SAVE)
        } catch (t: Throwable) {
            pendingSaveResult = null
            pendingSaveSourcePath = null
            result.error("SAVE_FAILED", t.message, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_SAVE) return false
        val pending = pendingSaveResult ?: return true
        val source = pendingSaveSourcePath
        pendingSaveResult = null
        pendingSaveSourcePath = null

        if (resultCode != Activity.RESULT_OK || data?.data == null || source == null) {
            pending.success(mapOf("saved" to false))
            return true
        }
        val uri: Uri = data.data!!
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use { out ->
                        File(source).inputStream().use { input -> input.copyTo(out) }
                    } ?: throw IllegalStateException("cannot open destination")
                }
                pending.success(mapOf("saved" to true, "uri" to uri.toString()))
            } catch (t: Throwable) {
                pending.success(mapOf("saved" to false, "reason" to (t.message ?: "write failed")))
            }
        }
        return true
    }

    private fun handleCancel(result: MethodChannel.Result) {
        currentJob?.cancel()
        currentJob = null
        result.success(null)
    }

    private fun buildClient(): OkHttpClient =
        OkHttpClient.Builder()
            .connectionPool(ConnectionPool(16, 5, TimeUnit.MINUTES))
            .protocols(listOf(Protocol.HTTP_2, Protocol.HTTP_1_1))
            .retryOnConnectionFailure(true)
            .followRedirects(true)
            .followSslRedirects(true)
            .cookieJar(WebViewCookieJar())
            .connectTimeout(12, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(0, TimeUnit.SECONDS)
            .build()

    companion object {
        private const val CHANNEL_METHOD = "com.aidocassistant.app/pdf_import"
        private const val CHANNEL_EVENT = "com.aidocassistant.app/pdf_import_progress"
        private const val REQ_SAVE = 0xF11E
    }
}

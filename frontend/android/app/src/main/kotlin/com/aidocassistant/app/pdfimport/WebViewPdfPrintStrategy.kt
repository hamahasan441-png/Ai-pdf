package com.aidocassistant.app.pdfimport

import android.annotation.SuppressLint
import android.os.Bundle
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import java.io.File

class WebViewPdfPrintStrategy(
    override val startDelayMs: Long = 2500L,
    private val pageLoadSettleMs: Long = 1200L,
) : AcquisitionStrategy {

    override val name: String = "WebViewPrint"

    @SuppressLint("SetJavaScriptEnabled")
    override suspend fun acquire(url: HttpUrl, ctx: AcquisitionContext): File =
        withContext(Dispatchers.Main) {
            val loaded = CompletableDeferred<Unit>()
            val webView = WebView(ctx.appContext)
            webView.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                loadWithOverviewMode = true
                useWideViewPort = true
                userAgentString = ctx.defaultHeaders["User-Agent"] ?: userAgentString
            }
            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, finishedUrl: String) {
                    if (!loaded.isCompleted) loaded.complete(Unit)
                }
            }
            webView.loadUrl(url.toString(), ctx.defaultHeaders)
            loaded.await()
            delay(pageLoadSettleMs)

            val out = ctx.scratchFile("print")
            try {
                printToFile(webView, out)
                out
            } catch (t: Throwable) {
                out.delete()
                throw t
            } finally {
                webView.destroy()
            }
        }

    private suspend fun printToFile(webView: WebView, out: File) {
        val adapter = webView.createPrintDocumentAdapter("pdf_import")
        val attrs = PrintAttributes.Builder()
            .setMediaSize(PrintAttributes.MediaSize.ISO_A4)
            .setResolution(PrintAttributes.Resolution("pdf", "pdf", 600, 600))
            .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
            .build()

        val layoutDone = CompletableDeferred<PrintDocumentInfo>()
        adapter.onLayout(
            null, attrs, CancellationSignal(),
            object : PrintDocumentAdapter.LayoutResultCallback() {
                override fun onLayoutFinished(info: PrintDocumentInfo, changed: Boolean) {
                    layoutDone.complete(info)
                }
                override fun onLayoutFailed(error: CharSequence?) {
                    layoutDone.completeExceptionally(
                        IllegalStateException("print layout failed: $error")
                    )
                }
            },
            Bundle(),
        )
        layoutDone.await()

        val pfd = ParcelFileDescriptor.open(
            out,
            ParcelFileDescriptor.MODE_READ_WRITE or
                ParcelFileDescriptor.MODE_CREATE or
                ParcelFileDescriptor.MODE_TRUNCATE,
        )
        val writeDone = CompletableDeferred<Unit>()
        adapter.onWrite(
            arrayOf(PageRange.ALL_PAGES), pfd, CancellationSignal(),
            object : PrintDocumentAdapter.WriteResultCallback() {
                override fun onWriteFinished(pages: Array<out PageRange>?) {
                    writeDone.complete(Unit)
                }
                override fun onWriteFailed(error: CharSequence?) {
                    writeDone.completeExceptionally(
                        IllegalStateException("print write failed: $error")
                    )
                }
            },
        )
        try {
            writeDone.await()
        } finally {
            runCatching { pfd.close() }
            runCatching { adapter.onFinish() }
        }
    }
}

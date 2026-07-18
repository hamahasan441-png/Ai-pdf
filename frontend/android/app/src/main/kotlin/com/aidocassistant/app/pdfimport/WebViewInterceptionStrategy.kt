package com.aidocassistant.app.pdfimport

import android.annotation.SuppressLint
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.io.File

class WebViewInterceptionStrategy(
    override val startDelayMs: Long = 800L,
    private val pageTimeoutMs: Long = 15_000L,
) : AcquisitionStrategy {

    override val name: String = "WebViewInterception"

    private val direct = DirectDownloadStrategy(startDelayMs = 0L)

    override suspend fun acquire(url: HttpUrl, ctx: AcquisitionContext): File {
        val captured = capturePdfRequest(url, ctx)
            ?: throw IllegalStateException("no PDF request observed in page")
        return direct.acquire(captured, ctx)
    }

    @SuppressLint("SetJavaScriptEnabled")
    private suspend fun capturePdfRequest(url: HttpUrl, ctx: AcquisitionContext): HttpUrl? =
        withContext(Dispatchers.Main) {
            val result = CompletableDeferred<HttpUrl?>()
            val webView = WebView(ctx.appContext)
            webView.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                userAgentString = ctx.defaultHeaders["User-Agent"] ?: userAgentString
            }

            webView.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView, request: WebResourceRequest,
                ): WebResourceResponse? {
                    val candidate = request.url?.toString().orEmpty()
                    if (looksLikePdf(candidate) && !result.isCompleted) {
                        candidate.toHttpUrlSafe()?.let { result.complete(it) }
                    }
                    return null
                }
            }

            webView.loadUrl(url.toString(), ctx.defaultHeaders)

            val captured = withTimeoutOrNull(pageTimeoutMs) { result.await() }
            webView.stopLoading()
            webView.destroy()
            captured
        }

    private fun looksLikePdf(candidate: String): Boolean {
        val lower = candidate.lowercase()
        if (lower.startsWith("data:application/pdf")) return true
        return Regex("""\.pdf(\?|#|$)""").containsMatchIn(lower)
    }

    private fun String.toHttpUrlSafe(): HttpUrl? = this.toHttpUrlOrNull()
}

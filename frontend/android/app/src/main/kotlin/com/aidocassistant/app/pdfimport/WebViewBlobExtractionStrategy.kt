package com.aidocassistant.app.pdfimport

import android.annotation.SuppressLint
import android.util.Base64
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.HttpUrl
import java.io.File
import java.io.RandomAccessFile

class WebViewBlobExtractionStrategy(
    override val startDelayMs: Long = 1200L,
    private val pageTimeoutMs: Long = 18_000L,
    private val settleMs: Long = 1000L,
) : AcquisitionStrategy {

    override val name: String = "WebViewBlobExtraction"

    @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
    override suspend fun acquire(url: HttpUrl, ctx: AcquisitionContext): File =
        withContext(Dispatchers.Main) {
            val out = ctx.scratchFile("blob")
            val raf = RandomAccessFile(out, "rw")
            val done = CompletableDeferred<Long>()

            val webView = WebView(ctx.appContext)
            webView.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                userAgentString = ctx.defaultHeaders["User-Agent"] ?: userAgentString
            }

            val bridge = object {
                @JavascriptInterface
                fun onChunk(b64: String, offset: String) {
                    val bytes = Base64.decode(b64, Base64.DEFAULT)
                    val pos = offset.toLongOrNull() ?: return
                    synchronized(raf) {
                        raf.seek(pos)
                        raf.write(bytes)
                    }
                    ctx.progress.update(pos + bytes.size, -1L)
                }

                @JavascriptInterface
                fun onComplete(total: String) {
                    done.complete(total.toLongOrNull() ?: raf.length())
                }

                @JavascriptInterface
                fun onError(reason: String) {
                    done.completeExceptionally(IllegalStateException("blob: $reason"))
                }
            }
            webView.addJavascriptInterface(bridge, "AndroidPdfBridge")

            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, finishedUrl: String) {
                    view.postDelayed({
                        view.evaluateJavascript(EXTRACT_BLOB_JS, null)
                    }, settleMs)
                }
            }
            webView.loadUrl(url.toString(), ctx.defaultHeaders)

            val total = withTimeoutOrNull(pageTimeoutMs) {
                try { done.await() } catch (_: Throwable) { null }
            }
            runCatching { raf.close() }
            webView.destroy()

            if (total == null || out.length() == 0L) {
                out.delete()
                throw IllegalStateException("no blob PDF found in page")
            }
            out
        }

    companion object {
        private val EXTRACT_BLOB_JS = """
        (async () => {
          try {
            const sel = document.querySelector(
              'embed[type="application/pdf"], iframe, object[type="application/pdf"]');
            let src = (sel && (sel.src || sel.data)) || window.__pdfBlobUrl || null;
            if (!src || src.indexOf('blob:') !== 0) {
              AndroidPdfBridge.onError('no-blob-source'); return;
            }
            const resp = await fetch(src);
            const buf = new Uint8Array(await resp.arrayBuffer());
            const CH = 512 * 1024;
            for (let o = 0; o < buf.length; o += CH) {
              const end = Math.min(o + CH, buf.length);
              let bin = '';
              for (let i = o; i < end; i++) bin += String.fromCharCode(buf[i]);
              AndroidPdfBridge.onChunk(btoa(bin), String(o));
            }
            AndroidPdfBridge.onComplete(String(buf.length));
          } catch (e) {
            AndroidPdfBridge.onError((e && e.message) || 'fetch-failed');
          }
        })();
        """.trimIndent()
    }
}

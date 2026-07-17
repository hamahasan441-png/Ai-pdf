package com.aidocassistant.app.pdfimport

import android.content.Context
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.ConnectionPool
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Protocol
import java.io.File
import java.util.Collections
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Races 5 legitimate acquisition strategies with staggered start delays.
 * First to produce a verified PDF wins; all others are cancelled.
 */
class PdfImportEngine private constructor(
    private val appContext: Context,
    private val client: OkHttpClient,
    private val strategies: List<AcquisitionStrategy>,
) {

    suspend fun import(
        url: String,
        destination: File,
        progress: ProgressSink = ProgressSink.NOOP,
    ): AcquisitionResult {
        val httpUrl = parseUrl(url)
            ?: return AcquisitionResult.NoPdfAvailable("invalid URL: $url")

        val workDir = File(appContext.cacheDir, "pdf_import").apply { mkdirs() }
        val ctx = AcquisitionContext(appContext, client, workDir, progress)
        val failures = Collections.synchronizedList(mutableListOf<AcquisitionResult.Failure>())
        val winner = CompletableDeferred<AcquisitionResult.Success>()
        val startedAt = System.currentTimeMillis()

        return coroutineScope {
            val remaining = AtomicInteger(strategies.size)

            val jobs = strategies.map { strategy ->
                launch {
                    try {
                        if (strategy.startDelayMs > 0) delay(strategy.startDelayMs)
                        if (winner.isCompleted || !isActive) return@launch

                        val file = strategy.acquire(httpUrl, ctx)
                        when (val verdict = PdfValidator.verify(file)) {
                            is PdfValidator.Verdict.Valid -> {
                                val finalized = finalize(file, destination)
                                winner.complete(
                                    AcquisitionResult.Success(
                                        file = finalized,
                                        strategyName = strategy.name,
                                        pageCount = verdict.pageCount,
                                        bytes = finalized.length(),
                                        elapsedMs = System.currentTimeMillis() - startedAt,
                                    )
                                )
                            }
                            PdfValidator.Verdict.Encrypted -> {
                                file.delete()
                                failures += AcquisitionResult.Failure(
                                    strategy.name, "PDF is password-protected/encrypted"
                                )
                            }
                            else -> {
                                file.delete()
                                failures += AcquisitionResult.Failure(
                                    strategy.name, "not a valid PDF ($verdict)"
                                )
                            }
                        }
                    } catch (ce: kotlinx.coroutines.CancellationException) {
                        throw ce
                    } catch (t: Throwable) {
                        failures += AcquisitionResult.Failure(
                            strategy.name, t.message ?: t.javaClass.simpleName, t,
                        )
                    } finally {
                        remaining.decrementAndGet()
                    }
                }
            }

            val watchdog = launch {
                jobs.forEach { it.join() }
                if (!winner.isCompleted) {
                    winner.completeExceptionally(AllFailedSignal)
                }
            }

            try {
                val success = winner.await()
                jobs.forEach { it.cancel() }
                watchdog.cancel()
                success
            } catch (_: AllFailedSignal) {
                classifyAllFailed(failures)
            } finally {
                jobs.forEach { runCatching { it.cancelAndJoin() } }
            }
        }
    }

    private fun finalize(part: File, destination: File): File {
        destination.parentFile?.mkdirs()
        if (destination.exists()) destination.delete()
        if (!part.renameTo(destination)) {
            part.copyTo(destination, overwrite = true)
            part.delete()
        }
        return destination
    }

    private fun classifyAllFailed(
        failures: List<AcquisitionResult.Failure>,
    ): AcquisitionResult {
        val onlyEncrypted = failures.isNotEmpty() &&
            failures.all { it.reason.contains("encrypted", ignoreCase = true) }
        if (onlyEncrypted) {
            return AcquisitionResult.NoPdfAvailable(
                "the document is password-protected"
            )
        }
        return AcquisitionResult.AllFailed(failures.toList())
    }

    private fun parseUrl(raw: String): HttpUrl? {
        val trimmed = raw.trim()
        val withScheme = if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            trimmed
        } else {
            "https://$trimmed"
        }
        return try { withScheme.toHttpUrl() } catch (_: IllegalArgumentException) { null }
    }

    private object AllFailedSignal : Exception() {
        private fun readResolve(): Any = AllFailedSignal
    }

    companion object {
        fun create(context: Context): PdfImportEngine {
            val appContext = context.applicationContext
            val client = OkHttpClient.Builder()
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

            return PdfImportEngine(
                appContext = appContext,
                client = client,
                // NOTE: WebViewPdfPrintStrategy was removed. It relied on
                // subclassing PrintDocumentAdapter.LayoutResultCallback /
                // WriteResultCallback, whose constructors are package-private in
                // android.print and cannot be accessed from Kotlin (2.x) or Java.
                // The 4 remaining strategies cover the vast majority of cases.
                strategies = listOf(
                    DirectDownloadStrategy(startDelayMs = 0L),
                    HtmlParseStrategy(startDelayMs = 400L),
                    WebViewInterceptionStrategy(startDelayMs = 800L),
                    WebViewBlobExtractionStrategy(startDelayMs = 1200L),
                ),
            )
        }
    }
}

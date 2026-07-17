package com.aidocassistant.app.pdfimport

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.Request
import java.io.File

class HtmlParseStrategy(
    override val startDelayMs: Long = 400L,
    private val maxCandidates: Int = 5,
) : AcquisitionStrategy {

    override val name: String = "HtmlParse"

    private val direct = DirectDownloadStrategy(startDelayMs = 0L)

    private val pdfAttrRegex = Regex(
        """(?:href|src|content)\s*=\s*["']([^"']+?\.pdf(?:\?[^"']*)?)["']""",
        RegexOption.IGNORE_CASE,
    )
    private val metaRefreshRegex = Regex(
        """url\s*=\s*([^;"'\s>]+\.pdf(?:\?[^"'\s>]*)?)""",
        RegexOption.IGNORE_CASE,
    )

    override suspend fun acquire(url: HttpUrl, ctx: AcquisitionContext): File {
        val html = fetchHtml(url, ctx)
        val candidates = extractCandidates(html, url)
        check(candidates.isNotEmpty()) { "no .pdf link found in page" }

        var lastError: Throwable? = null
        for (candidate in candidates.take(maxCandidates)) {
            try {
                return direct.acquire(candidate, ctx)
            } catch (t: Throwable) {
                lastError = t
            }
        }
        throw IllegalStateException("no candidate link yielded a downloadable PDF", lastError)
    }

    private suspend fun fetchHtml(url: HttpUrl, ctx: AcquisitionContext): String =
        withContext(Dispatchers.IO) {
            val hdrs = Headers.Builder().apply {
                ctx.defaultHeaders.forEach { (k, v) -> add(k, v) }
            }.build()
            val req = Request.Builder()
                .url(url)
                .headers(hdrs)
                .header("Accept", "text/html,application/xhtml+xml,*/*;q=0.8")
                .build()
            ctx.client.newCall(req).execute().use { resp ->
                check(resp.isSuccessful) { "HTTP ${resp.code} fetching page" }
                resp.body?.byteStream()?.bufferedReader()
                    ?.use { it.readText().take(4 * 1024 * 1024) }
                    ?: error("empty page body")
            }
        }

    private fun extractCandidates(html: String, base: HttpUrl): List<HttpUrl> {
        val raw = LinkedHashSet<String>()
        pdfAttrRegex.findAll(html).forEach { raw.add(it.groupValues[1]) }
        metaRefreshRegex.findAll(html).forEach { raw.add(it.groupValues[1]) }

        return raw.mapNotNull { link ->
            val decoded = link.replace("&amp;", "&").trim()
            base.resolve(decoded)
        }.distinct()
    }
}

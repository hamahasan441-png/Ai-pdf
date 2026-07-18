package com.aidocassistant.app.pdfimport

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Persists the progress of a parallel range download so it can resume across
 * app restarts (process death, crash, user backgrounding, or a manual pause).
 *
 * On disk, each download owns two deterministic files in the work dir, keyed by
 * a hash of the URL:
 *   - <key>.part : the pre-allocated destination, written to by positional seeks
 *   - <key>.meta : JSON describing segment layout + bytes completed per segment
 *
 * A resume is only honored when the server validator (ETag / Last-Modified) and
 * the total length still match what the meta recorded — otherwise the stale
 * partial is discarded and the download restarts cleanly (never corrupts data).
 */
class ResumeState private constructor(
    val partFile: File,
    private val metaFile: File,
    private val urlKey: String,
) {
    var segSize: Long = 0; private set
    var segCount: Int = 0; private set
    var contentLength: Long = 0; private set

    /** Bytes completed within each segment (index i covers [i*segSize .. ...]). */
    lateinit var written: LongArray
        private set

    /** True if this run picked up from an on-disk partial. */
    var resumed: Boolean = false; private set

    private var finalUrl: String = ""
    private var etag: String? = null
    private var lastModified: String? = null

    private val lock = Any()
    @Volatile private var lastPersistMs = 0L

    /** Live total of bytes completed across all segments. */
    fun bytesCompleted(): Long = synchronized(lock) { written.sum() }

    /**
     * Prepares state for [total] bytes. If a compatible partial exists it is
     * resumed; otherwise a fresh, pre-allocated part file is created.
     */
    fun prepare(
        total: Long,
        finalUrl: String,
        etag: String?,
        lastModified: String?,
        computeSegCount: (Long) -> Int,
    ) {
        this.contentLength = total
        this.finalUrl = finalUrl
        this.etag = etag
        this.lastModified = lastModified

        val existing = loadMeta()
        val validatorMatches = existing != null &&
            existing.optLong("len", -1) == total &&
            validatorMatch(existing, etag, lastModified)
        val partUsable = partFile.exists() && partFile.length() == total

        if (existing != null && validatorMatches && partUsable) {
            segSize = existing.getLong("segSize")
            segCount = existing.getInt("segCount")
            val arr = existing.getJSONArray("written")
            written = LongArray(segCount) { arr.optLong(it, 0L).coerceIn(0L, segLen(it)) }
            resumed = written.sum() > 0
        } else {
            // Fresh start: (re)allocate the part file and reset counters.
            discardOnDisk()
            segCount = computeSegCount(total).coerceAtLeast(1)
            segSize = Math.ceil(total.toDouble() / segCount).toLong()
            written = LongArray(segCount)
            resumed = false
            java.io.RandomAccessFile(partFile, "rw").use { it.setLength(total) }
            persist(force = true)
        }
    }

    fun segStart(i: Int): Long = i * segSize
    fun segEnd(i: Int): Long = minOf(segStart(i) + segSize - 1, contentLength - 1)
    private fun segLen(i: Int): Long = segEnd(i) - segStart(i) + 1

    /** Report cumulative bytes completed in segment [i]; persists throttled. */
    fun onSegmentProgress(i: Int, cumulativeInSegment: Long) {
        synchronized(lock) { written[i] = cumulativeInSegment }
        val now = System.currentTimeMillis()
        if (now - lastPersistMs > PERSIST_INTERVAL_MS) {
            lastPersistMs = now
            persist(force = false)
        }
    }

    fun persist(force: Boolean) {
        val snapshot: LongArray
        synchronized(lock) { snapshot = written.copyOf() }
        val json = JSONObject().apply {
            put("v", 1)
            put("url", urlKey)
            put("finalUrl", finalUrl)
            put("etag", etag ?: JSONObject.NULL)
            put("lastModified", lastModified ?: JSONObject.NULL)
            put("len", contentLength)
            put("segSize", segSize)
            put("segCount", segCount)
            put("written", JSONArray().apply { snapshot.forEach { put(it) } })
        }
        runCatching { metaFile.writeText(json.toString()) }
    }

    /** Download finished successfully: drop the meta (part file is the result). */
    fun complete() {
        runCatching { metaFile.delete() }
    }

    /** Remove both on-disk files (unrecoverable / discarded partial). */
    fun discardOnDisk() {
        runCatching { metaFile.delete() }
        runCatching { partFile.delete() }
    }

    private fun loadMeta(): JSONObject? = runCatching {
        if (!metaFile.exists()) return null
        JSONObject(metaFile.readText())
    }.getOrNull()

    private fun validatorMatch(meta: JSONObject, etag: String?, lastModified: String?): Boolean {
        val metaEtag = meta.optString("etag", "").ifBlank { null }
        val metaLm = meta.optString("lastModified", "").ifBlank { null }
        return when {
            etag != null && metaEtag != null -> etag == metaEtag
            lastModified != null && metaLm != null -> lastModified == metaLm
            // No shared validator -> cannot safely resume.
            else -> false
        }
    }

    companion object {
        private const val PERSIST_INTERVAL_MS = 750L
        private const val STALE_MS = 7L * 24 * 60 * 60 * 1000 // 7 days

        fun forUrl(workDir: File, url: String): ResumeState {
            workDir.mkdirs()
            val key = sha1(url)
            return ResumeState(
                partFile = File(workDir, "res_$key.part"),
                metaFile = File(workDir, "res_$key.meta"),
                urlKey = url,
            )
        }

        /** Best-effort sweep of resume files older than [STALE_MS]. */
        fun sweepStale(workDir: File) {
            val now = System.currentTimeMillis()
            workDir.listFiles { f ->
                (f.name.startsWith("res_") &&
                    (f.name.endsWith(".part") || f.name.endsWith(".meta")))
            }?.forEach { f ->
                if (now - f.lastModified() > STALE_MS) runCatching { f.delete() }
            }
        }

        private fun sha1(input: String): String {
            val md = MessageDigest.getInstance("SHA-1")
            return md.digest(input.toByteArray()).joinToString("") { "%02x".format(it) }
        }
    }
}

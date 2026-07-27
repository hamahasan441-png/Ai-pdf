package com.aidocassistant.app

import android.app.ActivityManager
import android.content.Context

/**
 * Low-RAM detector — E4.2 Enhancement-Based Masterplan.
 *
 * Uses ActivityManager.MemoryInfo to determine if device is low-RAM (<2GB totalMem)
 * or currently under memory pressure. This drives adaptive LRU caps:
 * - Low-RAM: cap LRU 1, raster 900px max edge, disable adjacent pre-render
 * - Normal: cap 3, 2400px, ±1 pre-render
 *
 * Also exposes threshold from ActivityManager.isLowRamDevice (API 19+).
 */
class LowRamDetector(private val context: Context) {

    data class MemoryInfo(
        val totalMem: Long,
        val availMem: Long,
        val lowMemory: Boolean,
        val isLowRamDevice: Boolean,
        val threshold: Long,
        val isLowRamMode: Boolean // our adaptive flag: totalMem < 2GB OR lowMemory OR isLowRamDevice
    )

    fun getMemoryInfo(): MemoryInfo {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)
        val isLowRamDevice = if (android.os.Build.VERSION.SDK_INT >= 19) {
            am.isLowRamDevice
        } else {
            false
        }
        val isLowRamMode = mi.totalMem < 2L * 1024 * 1024 * 1024 || mi.lowMemory || isLowRamDevice
        return MemoryInfo(
            totalMem = mi.totalMem,
            availMem = mi.availMem,
            lowMemory = mi.lowMemory,
            isLowRamDevice = isLowRamDevice,
            threshold = mi.threshold,
            isLowRamMode = isLowRamMode
        )
    }
}

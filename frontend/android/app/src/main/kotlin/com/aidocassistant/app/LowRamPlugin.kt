package com.aidocassistant.app

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter plugin exposing LowRamDetector to Dart via MethodChannel "low_ram_detector".
 *
 * Dart usage:
 * const channel = MethodChannel('low_ram_detector');
 * final info = await channel.invokeMethod<Map>('getMemoryInfo');
 * // info['isLowRamMode'] => bool
 */
class LowRamPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var detector: LowRamDetector

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "low_ram_detector")
        channel.setMethodCallHandler(this)
        detector = LowRamDetector(binding.applicationContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getMemoryInfo" -> {
                try {
                    val info = detector.getMemoryInfo()
                    result.success(mapOf(
                        "totalMem" to info.totalMem,
                        "availMem" to info.availMem,
                        "lowMemory" to info.lowMemory,
                        "isLowRamDevice" to info.isLowRamDevice,
                        "threshold" to info.threshold,
                        "isLowRamMode" to info.isLowRamMode
                    ))
                } catch (e: Exception) {
                    result.error("LOW_RAM_ERROR", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}

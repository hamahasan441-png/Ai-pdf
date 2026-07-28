import 'package:flutter/services.dart';

/// Low-RAM detector Dart wrapper — E4.2 Enhancement-Based Masterplan.
///
/// Uses MethodChannel "low_ram_detector" to query Android ActivityManager.MemoryInfo.
/// Falls back to false (normal mode) on iOS or if channel fails.

class MemoryInfo {
  final int totalMem;
  final int availMem;
  final bool lowMemory;
  final bool isLowRamDevice;
  final int threshold;
  final bool isLowRamMode;

  const MemoryInfo({
    required this.totalMem,
    required this.availMem,
    required this.lowMemory,
    required this.isLowRamDevice,
    required this.threshold,
    required this.isLowRamMode,
  });

  factory MemoryInfo.fromMap(Map<dynamic, dynamic> map) => MemoryInfo(
        totalMem: (map['totalMem'] as int?) ?? 0,
        availMem: (map['availMem'] as int?) ?? 0,
        lowMemory: map['lowMemory'] as bool? ?? false,
        isLowRamDevice: map['isLowRamDevice'] as bool? ?? false,
        threshold: (map['threshold'] as int?) ?? 0,
        isLowRamMode: map['isLowRamMode'] as bool? ?? false,
      );
}

class LowRamService {
  static const MethodChannel _channel = MethodChannel('low_ram_detector');
  const LowRamService();

  Future<MemoryInfo> getMemoryInfo() async {
    try {
      final result = await _channel.invokeMethod<Map>('getMemoryInfo');
      if (result != null) {
        return MemoryInfo.fromMap(result);
      }
    } catch (_) {
      // Channel not implemented (iOS, test) — assume normal mode
    }
    return const MemoryInfo(
      totalMem: 0,
      availMem: 0,
      lowMemory: false,
      isLowRamDevice: false,
      threshold: 0,
      isLowRamMode: false,
    );
  }

  Future<bool> isLowRamMode() async {
    final info = await getMemoryInfo();
    return info.isLowRamMode;
  }
}

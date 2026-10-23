import 'package:flutter/material.dart';

/// Reading modes for comfortable document viewing.
enum ReadingMode {
  normal,   // Default white background
  dark,     // Dark background, inverted for OLED comfort
  sepia,    // Warm sepia tone, reduces eye strain
  green,    // Low blue-light green tint
}

/// State for the reading experience controller.
class ReadingModeState {
  final ReadingMode mode;
  final double brightness; // 0.0 to 1.0 overlay dimming
  final bool continuousScroll; // single-page vs continuous
  final bool showThumbnails; // thumbnail sidebar visible
  final bool autoScroll; // auto-scroll for hands-free reading
  final double autoScrollSpeed; // pixels per second

  const ReadingModeState({
    this.mode = ReadingMode.normal,
    this.brightness = 1.0,
    this.continuousScroll = false,
    this.showThumbnails = false,
    this.autoScroll = false,
    this.autoScrollSpeed = 30.0,
  });

  ReadingModeState copyWith({
    ReadingMode? mode,
    double? brightness,
    bool? continuousScroll,
    bool? showThumbnails,
    bool? autoScroll,
    double? autoScrollSpeed,
  }) => ReadingModeState(
    mode: mode ?? this.mode,
    brightness: brightness ?? this.brightness,
    continuousScroll: continuousScroll ?? this.continuousScroll,
    showThumbnails: showThumbnails ?? this.showThumbnails,
    autoScroll: autoScroll ?? this.autoScroll,
    autoScrollSpeed: autoScrollSpeed ?? this.autoScrollSpeed,
  );

  /// The color filter matrix for this reading mode.
  ColorFilter? get colorFilter {
    switch (mode) {
      case ReadingMode.dark:
        // Invert, then turn the hue by 180° so colours keep their hue (a red
        // mark stays reddish, a photo is not a negative) while white paper
        // becomes black and black text white.
        return const ColorFilter.matrix([
          0.574, -1.430, -0.144, 0, 255,
          -0.426, -0.430, -0.144, 0, 255,
          -0.426, -1.430, 0.856, 0, 255,
          0, 0, 0, 1, 0,
        ]);
      case ReadingMode.sepia:
        return const ColorFilter.matrix([
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case ReadingMode.green:
        return const ColorFilter.matrix([
          0.8, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 0.7, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case ReadingMode.normal:
        return null;
    }
  }
}

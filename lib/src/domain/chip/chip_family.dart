// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/models/esp_chip_info.dart';

/// Resolves chip families from ESP ROM magic values.
class ChipFamilyResolver {
  static const Map<int, ChipFamily> _magicMap = <int, ChipFamily>{
    0xFFF0C101: ChipFamily.esp8266,
    0x00F01D83: ChipFamily.esp32,
    0x000007C6: ChipFamily.esp32s2,
    0x00000009: ChipFamily.esp32s3,
    0x6921506F: ChipFamily.esp32c3,
    0x001B4F18: ChipFamily.esp32c3,
  };

  /// Resolves a [ChipFamily] from a magic register value.
  static ChipFamily resolve(int magic) =>
      _magicMap[magic] ?? ChipFamily.unknown;

  /// Returns a human-readable family description.
  static String describe(ChipFamily family) {
    return switch (family) {
      ChipFamily.esp8266 => 'ESP8266',
      ChipFamily.esp32 => 'ESP32',
      ChipFamily.esp32s2 => 'ESP32-S2',
      ChipFamily.esp32s3 => 'ESP32-S3',
      ChipFamily.esp32c3 => 'ESP32-C3',
      ChipFamily.unknown => 'Unknown ESP device',
    };
  }
}

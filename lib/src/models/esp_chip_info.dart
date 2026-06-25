// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// Supported ESP chip families.
enum ChipFamily {
  /// The Espressif ESP8266 SoC.
  esp8266,

  /// The Espressif ESP32 SoC.
  esp32,

  /// The Espressif ESP32-S2 SoC.
  esp32s2,

  /// The Espressif ESP32-S3 SoC.
  esp32s3,

  /// The Espressif ESP32-C3 SoC.
  esp32c3,

  /// An unrecognised or unsupported chip.
  unknown,
}

/// Describes a detected ESP chip.
class EspChipInfo {
  /// Creates an [EspChipInfo].
  const EspChipInfo({
    required this.family,
    required this.description,
    required this.magicValue,
    required this.macAddress,
    this.flashSizeBytes,
  });

  /// The detected chip family.
  final ChipFamily family;

  /// The human-readable chip description.
  final String description;

  /// The magic register value used for detection.
  final int magicValue;

  /// The formatted MAC address.
  final String macAddress;

  /// The optional flash size in bytes.
  final int? flashSizeBytes;
}

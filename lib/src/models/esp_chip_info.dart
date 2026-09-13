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
    this.psramCapacityBytes,
    this.psramType,
    this.psramVendor,
    this.embeddedFlashBytes,
    this.flashVendor,
    this.chipRevision,
  });

  /// The detected chip family.
  final ChipFamily family;

  /// The human-readable chip description.
  final String description;

  /// The magic register value used for detection.
  final int magicValue;

  /// The formatted MAC address.
  final String macAddress;

  /// The optional external flash size in bytes (from SPI JEDEC).
  final int? flashSizeBytes;

  /// Embedded PSRAM capacity in bytes, or null if none / unknown.
  final int? psramCapacityBytes;

  /// PSRAM interface type string, e.g. "OPI" or "QSPI", or null.
  final String? psramType;

  /// PSRAM vendor string, e.g. "AP_3v3", or null.
  final String? psramVendor;

  /// Embedded flash size in bytes (distinct from external SPI flash), or null.
  final int? embeddedFlashBytes;

  /// Flash vendor string, e.g. "XMC", "GD", or null.
  final String? flashVendor;

  /// Chip silicon revision string, e.g. "v0.2", or null.
  final String? chipRevision;
}

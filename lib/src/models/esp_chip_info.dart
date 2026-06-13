// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// Supported ESP chip families.
enum ChipFamily { esp8266, esp32, esp32s2, esp32s3, esp32c3, unknown }

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

// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// The top-level ESP partition types.
enum PartitionType {
  /// Application (code) partition.
  app,

  /// Data partition.
  data,

  /// An unrecognised partition type.
  unknown,
}

/// Common ESP partition subtypes.
enum PartitionSubtype {
  /// Factory default application image.
  factory,

  /// OTA slot 0.
  ota0,

  /// OTA slot 1.
  ota1,

  /// Non-volatile storage (NVS) data partition.
  nvs,

  /// PHY RF calibration data partition.
  phy,

  /// Core-dump data partition.
  coredump,

  /// SPIFFS filesystem partition.
  spiffs,

  /// FAT filesystem partition.
  fat,

  /// An unrecognised partition subtype.
  unknown,
}

/// Describes a single ESP partition table entry.
class PartitionEntry {
  /// Creates a [PartitionEntry].
  const PartitionEntry({
    required this.type,
    required this.subtype,
    required this.offset,
    required this.size,
    required this.label,
    required this.flags,
  });

  /// The partition type.
  final PartitionType type;

  /// The partition subtype.
  final PartitionSubtype subtype;

  /// The flash offset.
  final int offset;

  /// The partition size in bytes.
  final int size;

  /// The ASCII partition label.
  final String label;

  /// The raw flags value.
  final int flags;

  /// Whether the partition is marked as encrypted.
  bool get isEncrypted => (flags & 0x01) != 0;
}

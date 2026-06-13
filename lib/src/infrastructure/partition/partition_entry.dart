// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// The top-level ESP partition types.
enum PartitionType { app, data, unknown }

/// Common ESP partition subtypes.
enum PartitionSubtype {
  factory,
  ota0,
  ota1,
  nvs,
  phy,
  coredump,
  spiffs,
  fat,
  unknown
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

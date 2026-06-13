// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// Describes SPI flash identity information.
class EspFlashInfo {
  /// Creates an [EspFlashInfo].
  const EspFlashInfo({
    required this.manufacturerId,
    required this.deviceId,
    required this.capacityId,
    this.manufacturerName,
    this.capacityBytes,
  });

  /// The JEDEC manufacturer identifier.
  final int manufacturerId;

  /// The JEDEC device identifier.
  final int deviceId;

  /// The JEDEC capacity identifier.
  final int capacityId;

  /// The optional manufacturer name.
  final String? manufacturerName;

  /// The optional decoded capacity in bytes.
  final int? capacityBytes;
}

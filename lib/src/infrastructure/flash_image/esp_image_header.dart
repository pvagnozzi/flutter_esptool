// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

/// The expected ESP image magic byte.
const int espImageMagic = 0xE9;

/// Supported flash bus modes in ESP boot images.
enum FlashMode {
  /// Quad I/O mode (command, address, and data on four lines).
  qio,

  /// Quad output mode (data on four lines, command and address on one).
  qout,

  /// Dual I/O mode (command, address, and data on two lines).
  dio,

  /// Dual output mode (data on two lines, command and address on one).
  dout,
}

/// Supported flash frequencies in ESP boot images.
enum FlashFreq {
  /// 40 MHz flash clock frequency.
  f40m,

  /// 26 MHz flash clock frequency.
  f26m,

  /// 20 MHz flash clock frequency.
  f20m,

  /// 80 MHz flash clock frequency.
  f80m,
}

/// Supported flash sizes in ESP boot images.
enum FlashSize {
  /// 1 MB flash.
  s1mb,

  /// 2 MB flash.
  s2mb,

  /// 4 MB flash.
  s4mb,

  /// 8 MB flash.
  s8mb,

  /// 16 MB flash.
  s16mb,
}

/// Describes a single ESP image segment.
class EspImageSegment {
  /// Creates an [EspImageSegment].
  const EspImageSegment({required this.loadAddress, required this.data});

  /// The segment load address.
  final int loadAddress;

  /// The segment data bytes.
  final Uint8List data;
}

/// Describes a parsed ESP image header and its segments.
class EspImageHeader {
  /// Creates an [EspImageHeader].
  const EspImageHeader({
    required this.magic,
    required this.segmentCount,
    required this.flashMode,
    required this.flashSize,
    required this.flashFreq,
    required this.entryPoint,
    required this.segments,
  });

  /// The raw magic byte.
  final int magic;

  /// The number of image segments.
  final int segmentCount;

  /// The encoded flash mode.
  final FlashMode flashMode;

  /// The encoded flash size.
  final FlashSize flashSize;

  /// The encoded flash frequency.
  final FlashFreq flashFreq;

  /// The image entry point.
  final int entryPoint;

  /// The parsed image segments.
  final List<EspImageSegment> segments;

  /// Whether this header contains the expected magic value.
  bool get isValid => magic == espImageMagic;
}

// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/models/esp_progress.dart';

/// Defines parameters for a flash write operation.
class FlashParameters {
  /// Creates [FlashParameters].
  const FlashParameters({
    required this.offset,
    required this.data,
    this.compress = false,
    this.verify = false,
    this.eraseAll = false,
    this.onProgress,
  });

  /// The target flash offset.
  final int offset;

  /// The image bytes to write.
  final Uint8List data;

  /// Whether to use deflate-based write commands.
  final bool compress;

  /// Whether to verify the written bytes.
  final bool verify;

  /// Whether to request a full-chip erase.
  final bool eraseAll;

  /// The optional progress callback.
  final Stream<EspProgress> Function(EspProgress progress)? onProgress;
}

/// Defines parameters for a flash read operation.
class FlashReadParameters {
  /// Creates [FlashReadParameters].
  // coverage:ignore-start
  const FlashReadParameters({
    required this.offset,
    required this.size,
    this.onProgress,
  });
  // coverage:ignore-end

  /// The flash offset to read from.
  final int offset;

  /// The number of bytes to read.
  final int size;

  /// The optional progress callback.
  final Stream<EspProgress> Function(EspProgress progress)? onProgress;
}

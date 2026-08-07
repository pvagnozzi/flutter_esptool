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
    this.encrypted = false,
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

  /// When true, tells the ROM bootloader to encrypt [data] on-the-fly with
  /// the already-burned flash-encryption key (XTS-AES-128, BLOCK_KEY0) as it
  /// writes each block — equivalent to esptool.py's `--encrypt` flag.
  ///
  /// This is how a plaintext image can be correctly written to a device that
  /// already has flash encryption active: the ROM (not the host) holds the
  /// key and performs the encryption internally, so the host never needs to
  /// read the (read-protected) key back.
  ///
  /// Only supported in **ROM-loader mode** (no flasher stub loaded) — the
  /// stub's FLASH_BEGIN payload has no room for this field and does not
  /// implement on-the-fly encryption. Also only meaningful when
  /// [compress] is false: the ROM cannot both decompress and encrypt a
  /// block in the same pass.
  final bool encrypted;

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

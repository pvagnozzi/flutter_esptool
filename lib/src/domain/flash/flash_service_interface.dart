// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/domain/flash/flash_parameters.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';

/// Describes flash operations supported by the package.
abstract interface class FlashServiceInterface {
  /// Writes a flash image using [params].
  Future<Result<void>> writeFlash(FlashParameters params);

  /// Reads flash bytes using [params].
  Future<Result<Uint8List>> readFlash(FlashReadParameters params);

  /// Erases flash, optionally scoped to [offset] and [size].
  Future<Result<void>> eraseFlash({int? offset, int? size});

  /// Erases a flash region using the ROM bootloader FLASH_BEGIN erase path.
  ///
  /// Sends FLASH_BEGIN with [eraseSize] bytes to erase starting at [offset]
  /// and zero data blocks, then immediately sends FLASH_END.  This is the
  /// only erase mechanism supported by the ESP32-S3 ROM (opcode 0xD0 and
  /// 0xD1 are stub-only).  [eraseSize] must be a multiple of 4096.
  Future<Result<void>> eraseRegionRom({
    required int offset,
    required int eraseSize,
  });

  /// Computes the device MD5 for the flash range.
  Future<Result<String>> md5Flash(int offset, int size);
}

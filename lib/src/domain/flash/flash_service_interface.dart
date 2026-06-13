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

  /// Computes the device MD5 for the flash range.
  Future<Result<String>> md5Flash(int offset, int size);
}

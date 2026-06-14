// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';

/// Wraps zlib compression and decompression helpers.
class ZlibHelper {
  /// Compresses [data] with zlib.
  static Result<Uint8List> compress(Uint8List data) {
    try {
      final compressed = ZLibCodec().encode(data);
      return Success<Uint8List>(Uint8List.fromList(compressed));
    } catch (error, stackTrace) {
      // coverage:ignore-start
      // ZLibCodec.encode(Uint8List) has no practical invalid input; this keeps
      // the public Result API defensive if the runtime codec throws.
      return Failure<Uint8List>(
        EspError(
          type: EspErrorType.compressionError,
          message: error.toString(),
          stackTrace: stackTrace,
        ),
      );
      // coverage:ignore-end
    }
  }

  /// Decompresses zlib [data].
  static Result<Uint8List> decompress(Uint8List data) {
    try {
      final decompressed = ZLibCodec().decode(data);
      return Success<Uint8List>(Uint8List.fromList(decompressed));
    } catch (error, stackTrace) {
      return Failure<Uint8List>(
        EspError(
          type: EspErrorType.compressionError,
          message: error.toString(),
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

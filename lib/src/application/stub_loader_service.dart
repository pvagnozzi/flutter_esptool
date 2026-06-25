// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/domain/stub/stub_loader_interface.dart';
import 'package:flutter_esptool/src/models/esp_chip_info.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';

/// Placeholder stub loader implementation.
class StubLoaderService implements StubLoaderInterface {
  /// Whether the stub is currently loaded into device RAM.
  ///
  /// This placeholder always returns `false`.
  @override
  bool get isLoaded => false;

  /// Always returns [EspErrorType.stubNotAvailable].
  ///
  /// Bundle esptool stub binaries as Flutter assets and provide a
  /// custom [StubLoaderInterface] implementation for production use.
  @override
  Future<Result<void>> loadStub(ChipFamily family) async {
    return const Failure<void>(
      EspError(
        type: EspErrorType.stubNotAvailable,
        message:
            'Stub binaries not bundled. Bundle esptool stub assets for production use.',
      ),
    );
  }
}

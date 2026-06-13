// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/domain/stub/stub_loader_interface.dart';
import 'package:flutter_esptool/src/models/esp_chip_info.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';

/// Placeholder stub loader implementation.
class StubLoaderService implements StubLoaderInterface {
  @override
  bool get isLoaded => false;

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

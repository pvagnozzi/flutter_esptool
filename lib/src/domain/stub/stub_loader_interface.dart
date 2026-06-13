// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/models/esp_chip_info.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';

/// Describes a stub loader service.
abstract interface class StubLoaderInterface {
  /// Loads a RAM-resident flasher stub for [family].
  Future<Result<void>> loadStub(ChipFamily family);

  /// Whether a stub is currently loaded.
  bool get isLoaded;
}

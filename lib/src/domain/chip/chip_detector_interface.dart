// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/models/esp_chip_info.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';

/// Describes a chip detection service.
abstract interface class ChipDetectorInterface {
  /// Detects the connected chip and returns its metadata.
  Future<Result<EspChipInfo>> detect();
}

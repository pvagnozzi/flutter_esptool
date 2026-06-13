// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

/// Public API for the flutter_esptool package.
library;

export 'package:flutter_esptool/src/application/chip_detection_service.dart';
export 'package:flutter_esptool/src/application/connection_service.dart';
export 'package:flutter_esptool/src/application/flash_service.dart';
export 'package:flutter_esptool/src/application/info_service.dart';
export 'package:flutter_esptool/src/application/stub_loader_service.dart';
export 'package:flutter_esptool/src/domain/chip/chip_detector_interface.dart';
export 'package:flutter_esptool/src/domain/chip/chip_family.dart';
export 'package:flutter_esptool/src/domain/flash/flash_parameters.dart';
export 'package:flutter_esptool/src/domain/flash/flash_service_interface.dart';
export 'package:flutter_esptool/src/domain/stub/stub_loader_interface.dart';
export 'package:flutter_esptool/src/infrastructure/flash_image/esp_image_header.dart';
export 'package:flutter_esptool/src/infrastructure/flash_image/esp_image_parser.dart';
export 'package:flutter_esptool/src/infrastructure/flash_image/flash_image_builder.dart';
export 'package:flutter_esptool/src/infrastructure/partition/partition_entry.dart';
export 'package:flutter_esptool/src/infrastructure/partition/partition_table.dart';
export 'package:flutter_esptool/src/models/esp_chip_info.dart';
export 'package:flutter_esptool/src/models/esp_command.dart';
export 'package:flutter_esptool/src/models/esp_config.dart';
export 'package:flutter_esptool/src/models/esp_error.dart';
export 'package:flutter_esptool/src/models/esp_flash_info.dart';
export 'package:flutter_esptool/src/models/esp_progress.dart';
export 'package:flutter_esptool/src/models/esp_result.dart';
export 'package:flutter_esptool/src/transport/esp_transport.dart';
export 'package:flutter_esptool/src/transport/esp_transport_interface.dart';
export 'package:platform_serial/platform_serial.dart';

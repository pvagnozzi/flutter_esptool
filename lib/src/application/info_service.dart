// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/application/chip_detection_service.dart';
import 'package:flutter_esptool/src/models/esp_chip_info.dart';
import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_flash_info.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';

/// Provides chip and flash information queries.
class InfoService {
  /// Creates an [InfoService].
  InfoService({
    required EspTransportInterface transport,
    ChipDetectionService? chipDetectionService,
  })  : _transport = transport,
        _chipDetectionService =
            chipDetectionService ?? ChipDetectionService(transport);

  final EspTransportInterface _transport;
  final ChipDetectionService _chipDetectionService;

  /// Queries the device for its flash JEDEC identifier.
  Future<Result<EspFlashInfo>> getFlashId() async {
    try {
      final request = Uint8List(24);
      request[0] = 0x9F;
      final response = await _transport.sendCommand(
        EspCommand(opcode: EspCommandOpcode.spiSetParams, data: request),
      );
      if (!response.isSuccess) {
        return const Failure<EspFlashInfo>(
          EspError(
            type: EspErrorType.flashReadFailed,
            message: 'Unable to query flash identification',
          ),
        );
      }

      final raw = response.data.length >= 3
          ? response.data
          : Uint8List.fromList(<int>[
              response.value & 0xFF,
              (response.value >> 8) & 0xFF,
              (response.value >> 16) & 0xFF,
            ]);
      final manufacturerId = raw[0];
      final deviceId = raw.length > 1 ? raw[1] : 0;
      final capacityId = raw.length > 2 ? raw[2] : 0;
      return Success<EspFlashInfo>(
        EspFlashInfo(
          manufacturerId: manufacturerId,
          deviceId: deviceId,
          capacityId: capacityId,
          manufacturerName: _manufacturerName(manufacturerId),
          capacityBytes: _capacityBytes(capacityId),
        ),
      );
    } catch (error, stackTrace) {
      return Failure<EspFlashInfo>(
        EspError(
          type: EspErrorType.flashReadFailed,
          message: error.toString(),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Returns the currently connected chip metadata.
  Future<Result<EspChipInfo>> getChipInfo() => _chipDetectionService.detect();

  /// Returns the device MAC address.
  Future<Result<String>> getMac() async {
    final result = await _chipDetectionService.detect();
    return result.map((chip) => chip.macAddress);
  }

  String? _manufacturerName(int manufacturerId) {
    return switch (manufacturerId) {
      0x20 => 'Micron',
      0xC8 => 'GigaDevice',
      0xEF => 'Winbond',
      _ => null,
    };
  }

  int? _capacityBytes(int capacityId) {
    if (capacityId < 0x11) {
      return null;
    }
    return 1 << capacityId;
  }
}

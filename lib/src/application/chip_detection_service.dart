// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/domain/chip/chip_detector_interface.dart';
import 'package:flutter_esptool/src/domain/chip/chip_family.dart';
import 'package:flutter_esptool/src/models/esp_chip_info.dart';
import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';

/// Detects ESP chips using ROM register reads.
class ChipDetectionService implements ChipDetectorInterface {
  /// Creates a [ChipDetectionService].
  ChipDetectionService(this._transport);

  static const int _chipMagicRegister = 0x40001000;
  static const int _esp8266MacLowRegister = 0x3FF00050;
  static const int _esp8266MacHighRegister = 0x3FF00054;
  static const int _esp32MacLowRegister = 0x6001A044;
  static const int _esp32MacHighRegister = 0x6001A048;

  final EspTransportInterface _transport;

  @override
  Future<Result<EspChipInfo>> detect() async {
    try {
      final magic = await _readRegister(_chipMagicRegister);
      final family = ChipFamilyResolver.resolve(magic);
      if (family == ChipFamily.unknown) {
        return Failure<EspChipInfo>(
          EspError(
            type: EspErrorType.invalidChip,
            message: 'Unknown chip magic value 0x${magic.toRadixString(16)}',
          ),
        );
      }

      final macAddress = await _readMacAddress(family);
      return Success<EspChipInfo>(
        EspChipInfo(
          family: family,
          description: ChipFamilyResolver.describe(family),
          magicValue: magic,
          macAddress: macAddress,
        ),
      );
    } catch (error, stackTrace) {
      final espError = error is EspError
          ? error
          : EspError(
              type: EspErrorType.invalidChip,
              message: error.toString(),
              stackTrace: stackTrace,
            );
      return Failure<EspChipInfo>(espError);
    }
  }

  Future<int> _readRegister(int address) async {
    final data = Uint8List(4);
    ByteData.sublistView(data).setUint32(0, address, Endian.little);
    final response = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.readReg, data: data),
    );
    if (!response.isSuccess) {
      throw EspError(
        type: EspErrorType.invalidResponse,
        message: 'Failed to read register 0x${address.toRadixString(16)}',
      );
    }
    return response.value;
  }

  Future<String> _readMacAddress(ChipFamily family) async {
    final lowAddress = family == ChipFamily.esp8266
        ? _esp8266MacLowRegister
        : _esp32MacLowRegister;
    final highAddress = family == ChipFamily.esp8266
        ? _esp8266MacHighRegister
        : _esp32MacHighRegister;
    final low = await _readRegister(lowAddress);
    final high = await _readRegister(highAddress);

    final bytes = <int>[
      (high >> 8) & 0xFF,
      high & 0xFF,
      (low >> 24) & 0xFF,
      (low >> 16) & 0xFF,
      (low >> 8) & 0xFF,
      low & 0xFF,
    ];
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }
}

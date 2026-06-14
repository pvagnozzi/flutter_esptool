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
      final chipResult = await _chipDetectionService.detect();
      if (chipResult is Failure<EspChipInfo>) {
        return Failure<EspFlashInfo>(chipResult.error);
      }
      final family = (chipResult as Success<EspChipInfo>).value.family;
      final registerMap = _registerMapForFamily(family);
      if (registerMap == null) {
        return const Failure<EspFlashInfo>(
          EspError(
            type: EspErrorType.unsupportedOperation,
            message: 'Flash ID is not supported for this chip family',
          ),
        );
      }

      await _attachSpiFlashIfNeeded(family);
      final rawId = await _runSpiFlashReadJedecId(registerMap);
      final raw = Uint8List.fromList(<int>[
        rawId & 0xFF,
        (rawId >> 8) & 0xFF,
        (rawId >> 16) & 0xFF,
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

  Future<void> _attachSpiFlashIfNeeded(ChipFamily family) async {
    if (family == ChipFamily.esp8266) {
      return;
    }
    final payload = Uint8List(8);
    final response = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.spiAttach, data: payload),
    );
    if (!response.isSuccess) {
      return;
    }
  }

  Future<int> _runSpiFlashReadJedecId(_SpiRegisterMap map) async {
    const spiUsrCommand = 1 << 31;
    const spiUsrMiso = 1 << 28;
    const spiCmdUsr = 1 << 18;
    const spiUsr2CommandLenShift = 28;
    const spiflashRdid = 0x9F;
    const readBits = 24;
    const spiUsrAddrLenShift = 26;
    const spiMosiBitLenShift = 17;
    const spiMisoBitLenShift = 8;

    final spiCmdReg = map.base + 0x00;
    final spiUsrReg = map.base + map.spiUsrOffset;
    final spiUsr1Reg = map.base + map.spiUsr1Offset;
    final spiUsr2Reg = map.base + map.spiUsr2Offset;
    final spiW0Reg = map.base + map.spiW0Offset;

    final oldUsr = await _readRegister(spiUsrReg);
    final oldUsr2 = await _readRegister(spiUsr2Reg);
    try {
      if (map.spiMisoDlenOffset != null) {
        final spiMisoDlenReg = map.base + map.spiMisoDlenOffset!;
        await _writeRegister(spiMisoDlenReg, readBits - 1);
        if (map.spiMosiDlenOffset != null) {
          final spiMosiDlenReg = map.base + map.spiMosiDlenOffset!;
          await _writeRegister(spiMosiDlenReg, 0);
        }
      } else {
        const flags = ((readBits - 1) << spiMisoBitLenShift) |
            (0 << spiMosiBitLenShift) |
            (0 << spiUsrAddrLenShift);
        await _writeRegister(spiUsr1Reg, flags);
      }

      await _writeRegister(spiUsrReg, spiUsrCommand | spiUsrMiso);
      await _writeRegister(
        spiUsr2Reg,
        (7 << spiUsr2CommandLenShift) | spiflashRdid,
      );
      await _writeRegister(spiW0Reg, 0);
      await _writeRegister(spiCmdReg, spiCmdUsr);

      for (var index = 0; index < 10; index++) {
        final value = await _readRegister(spiCmdReg);
        if ((value & spiCmdUsr) == 0) {
          final status = await _readRegister(spiW0Reg);
          return status;
        }
      }
      throw const EspError(
        type: EspErrorType.timeout,
        message: 'SPI command did not complete in time',
      );
    } finally {
      await _writeRegister(spiUsrReg, oldUsr);
      await _writeRegister(spiUsr2Reg, oldUsr2);
    }
  }

  Future<int> _readRegister(int address) async {
    final payload = Uint8List(4);
    ByteData.sublistView(payload).setUint32(0, address, Endian.little);
    final response = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.readReg, data: payload),
    );
    if (!response.isSuccess) {
      throw EspError(
        type: EspErrorType.invalidResponse,
        message: 'Failed to read register 0x${address.toRadixString(16)}',
      );
    }
    return response.value;
  }

  Future<void> _writeRegister(int address, int value) async {
    final payload = Uint8List(16);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, address, Endian.little);
    data.setUint32(4, value, Endian.little);
    data.setUint32(8, 0xFFFFFFFF, Endian.little);
    data.setUint32(12, 0, Endian.little);
    final response = await _transport.sendCommand(
      EspCommand(opcode: EspCommandOpcode.writeReg, data: payload),
    );
    if (!response.isSuccess) {
      throw EspError(
        type: EspErrorType.invalidResponse,
        message: 'Failed to write register 0x${address.toRadixString(16)}',
      );
    }
  }

  _SpiRegisterMap? _registerMapForFamily(ChipFamily family) {
    return switch (family) {
      ChipFamily.esp8266 => const _SpiRegisterMap(
          base: 0x60000200,
          spiUsrOffset: 0x1C,
          spiUsr1Offset: 0x20,
          spiUsr2Offset: 0x24,
          spiW0Offset: 0x40,
        ),
      ChipFamily.esp32 => const _SpiRegisterMap(
          base: 0x3FF42000,
          spiUsrOffset: 0x1C,
          spiUsr1Offset: 0x20,
          spiUsr2Offset: 0x24,
          spiMosiDlenOffset: 0x28,
          spiMisoDlenOffset: 0x2C,
          spiW0Offset: 0x80,
        ),
      ChipFamily.esp32s2 => const _SpiRegisterMap(
          base: 0x3F402000,
          spiUsrOffset: 0x18,
          spiUsr1Offset: 0x1C,
          spiUsr2Offset: 0x20,
          spiMosiDlenOffset: 0x24,
          spiMisoDlenOffset: 0x28,
          spiW0Offset: 0x58,
        ),
      ChipFamily.esp32s3 || ChipFamily.esp32c3 => const _SpiRegisterMap(
          base: 0x60002000,
          spiUsrOffset: 0x18,
          spiUsr1Offset: 0x1C,
          spiUsr2Offset: 0x20,
          spiMosiDlenOffset: 0x24,
          spiMisoDlenOffset: 0x28,
          spiW0Offset: 0x58,
        ),
      ChipFamily.unknown => null,
    };
  }
}

class _SpiRegisterMap {
  const _SpiRegisterMap({
    required this.base,
    required this.spiUsrOffset,
    required this.spiUsr1Offset,
    required this.spiUsr2Offset,
    required this.spiW0Offset,
    this.spiMosiDlenOffset,
    this.spiMisoDlenOffset,
  });

  final int base;
  final int spiUsrOffset;
  final int spiUsr1Offset;
  final int spiUsr2Offset;
  final int spiW0Offset;
  final int? spiMosiDlenOffset;
  final int? spiMisoDlenOffset;
}

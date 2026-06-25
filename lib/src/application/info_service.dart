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

  /// Reads [size] bytes from flash at [offset] using direct SPI register
  /// manipulation (like JEDEC-ID reading).  Works with the ROM bootloader
  /// without requiring the esptool stub or the [spiSetParams] command.
  ///
  /// Reads in 32-byte chunks (256 bits per SPI transaction).  On chips that
  /// report [ChipFamily.unknown] or ESP8266 this always returns an error.
  Future<Result<Uint8List>> readFlashViaSpi(int offset, int size) async {
    if (size <= 0) {
      return const Failure<Uint8List>(
        EspError(
          type: EspErrorType.flashReadFailed,
          message: 'Read size must be positive',
        ),
      );
    }
    try {
      final chipResult = await _chipDetectionService.detect();
      if (chipResult is Failure<EspChipInfo>) {
        return Failure<Uint8List>((chipResult).error);
      }
      final family = (chipResult as Success<EspChipInfo>).value.family;
      if (family == ChipFamily.esp8266) {
        return const Failure<Uint8List>(
          EspError(
            type: EspErrorType.unsupportedOperation,
            message: 'Direct SPI flash read is not supported on ESP8266',
          ),
        );
      }
      final registerMap = _registerMapForFamily(family);
      if (registerMap == null) {
        return const Failure<Uint8List>(
          EspError(
            type: EspErrorType.unsupportedOperation,
            message: 'Unsupported chip family for direct SPI flash read',
          ),
        );
      }
      await _attachSpiFlashIfNeeded(family);

      const chunkBytes = 32;
      final output = BytesBuilder(copy: false);
      var readSoFar = 0;
      while (readSoFar < size) {
        final chunkSize = (size - readSoFar).clamp(0, chunkBytes);
        final chunkData = await _readSpiFlashChunk(
          registerMap,
          offset + readSoFar,
          chunkSize,
        );
        output.add(chunkData);
        readSoFar += chunkSize;
      }
      return Success<Uint8List>(output.toBytes());
    } catch (error, stackTrace) {
      return Failure<Uint8List>(
        EspError(
          type: EspErrorType.flashReadFailed,
          message: error.toString(),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Reads up to 32 bytes from [flashAddress] via SPI register manipulation.
  Future<Uint8List> _readSpiFlashChunk(
    _SpiRegisterMap map,
    int flashAddress,
    int bytesToRead,
  ) async {
    if (bytesToRead <= 0 || bytesToRead > 32) {
      throw const EspError(
        type: EspErrorType.flashReadFailed,
        message: 'SPI chunk read: bytesToRead must be 1..32',
      );
    }

    const spiCmdUsr = 1 << 18;
    const spiUsrCommand = 1 << 31;
    const spiUsrAddr = 1 << 26;
    const spiUsrMiso = 1 << 28;
    const spiUsr2CommandLenShift = 28;
    const spiUsrAddrLenShift = 26;
    const spiflashRead = 0x03;

    final spiCmdReg = map.base + 0x00;
    final spiAddrReg = map.base + 0x04; // SPI_ADDR
    final spiUsrReg = map.base + map.spiUsrOffset;
    final spiUsr1Reg = map.base + map.spiUsr1Offset;
    final spiUsr2Reg = map.base + map.spiUsr2Offset;
    final spiW0Reg = map.base + map.spiW0Offset;

    final readBits = bytesToRead * 8;

    final oldUsr = await _readRegister(spiUsrReg);
    final oldUsr2 = await _readRegister(spiUsr2Reg);
    final oldUsr1 = await _readRegister(spiUsr1Reg);
    try {
      if (map.spiMisoDlenOffset != null) {
        final spiMisoDlenReg = map.base + map.spiMisoDlenOffset!;
        await _writeRegister(spiMisoDlenReg, readBits - 1);
        if (map.spiMosiDlenOffset != null) {
          final spiMosiDlenReg = map.base + map.spiMosiDlenOffset!;
          await _writeRegister(spiMosiDlenReg, 0);
        }
      }

      // addr_bitlen = 23 (24-bit address); set in USR1
      const addrBitlen = 23;
      final newUsr1 =
          (oldUsr1 & 0x03FFFFFF) | (addrBitlen << spiUsrAddrLenShift);
      await _writeRegister(spiUsr1Reg, newUsr1);

      // USR: command phase + address phase + MISO phase
      await _writeRegister(spiUsrReg, spiUsrCommand | spiUsrAddr | spiUsrMiso);

      // USR2: 8-bit READ command (0x03)
      await _writeRegister(
          spiUsr2Reg, (7 << spiUsr2CommandLenShift) | spiflashRead);

      // ADDR: flash address left-shifted by 8 (address in bits [31:8])
      await _writeRegister(spiAddrReg, flashAddress << 8);

      // Trigger the SPI transaction
      await _writeRegister(spiCmdReg, spiCmdUsr);

      // Poll until transaction completes
      for (var i = 0; i < 16; i++) {
        final cmdVal = await _readRegister(spiCmdReg);
        if ((cmdVal & spiCmdUsr) == 0) {
          // Read W registers — each is 4 bytes, little-endian
          final wordCount = (bytesToRead + 3) ~/ 4;
          final result = Uint8List(wordCount * 4);
          final resultData = ByteData.sublistView(result);
          for (var w = 0; w < wordCount; w++) {
            final word = await _readRegister(spiW0Reg + w * 4);
            resultData.setUint32(w * 4, word, Endian.little);
          }
          return result.sublist(0, bytesToRead);
        }
      }
      throw const EspError(
        type: EspErrorType.timeout,
        message: 'SPI READ command did not complete in time',
      );
    } finally {
      await _writeRegister(spiUsr1Reg, oldUsr1);
      await _writeRegister(spiUsrReg, oldUsr);
      await _writeRegister(spiUsr2Reg, oldUsr2);
    }
  }

  String? _manufacturerName(int manufacturerId) {
    return switch (manufacturerId) {
      0x1C => 'EON',
      0x20 => 'Micron',
      0xA1 => 'Fudan Micro',
      0xC2 => 'Macronix',
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

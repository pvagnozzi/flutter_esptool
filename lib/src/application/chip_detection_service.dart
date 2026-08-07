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
  static const int _esp32EfuseBaseRegister = 0x3FF5A000;
  static const int _esp32EfuseMacWord1Register =
      _esp32EfuseBaseRegister + 0x004;
  static const int _esp32EfuseMacWord2Register =
      _esp32EfuseBaseRegister + 0x008;
  static const int _esp32EfuseMacPrimeRegister =
      _esp32EfuseBaseRegister + 0x00C;
  static const int _esp32MacLowRegister = 0x6001A044;
  static const int _esp32MacHighRegister = 0x6001A048;

  // ESP32-S3 eFuse BLOCK1 registers (verified against esptool.py source).
  // EFUSE_BASE = 0x60007000, BLOCK1 starts at EFUSE_BASE + 0x44 = 0x60007044.
  // word3 = BLOCK1 + 4*3 = 0x60007050
  // word4 = BLOCK1 + 4*4 = 0x60007054
  // word5 = BLOCK1 + 4*5 = 0x60007058
  static const int _esp32s3EfuseWord3 = 0x60007050;
  static const int _esp32s3EfuseWord4 = 0x60007054;
  static const int _esp32s3EfuseWord5 = 0x60007058;

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

      // Read ESP32-S3 eFuse words to extract PSRAM, flash vendor, and chip
      // revision information.  These are best-effort — if any register read
      // fails (e.g. from ROM bootloader without the flasher stub), we simply
      // leave the corresponding fields as null.
      int? psramCapacityBytes;
      String? psramType;
      String? psramVendor;
      int? embeddedFlashBytes;
      String? flashVendor;
      String? chipRevision;

      if (family == ChipFamily.esp32s3) {
        try {
          final word3 = await _readRegister(_esp32s3EfuseWord3);
          final word4 = await _readRegister(_esp32s3EfuseWord4);
          final word5 = await _readRegister(_esp32s3EfuseWord5);

          // Chip revision: rev_major from word5[25:24], rev_minor from
          // word5[23] (high bit) and word3[20:18] (low 3 bits).
          final revMajor = (word5 >> 24) & 0x03;
          final revMinorHi = (word5 >> 23) & 0x01;
          final revMinorLow = (word3 >> 18) & 0x07;
          final revMinor = (revMinorHi << 3) | revMinorLow;
          chipRevision = 'v$revMajor.$revMinor';

          // Embedded flash capacity (pkg_version / flash_cap from word3).
          final flashCap = (word3 >> 27) & 0x07;
          embeddedFlashBytes = switch (flashCap) {
            1 => 8 * 1024 * 1024,
            2 => 4 * 1024 * 1024,
            _ => null, // 0 = no embedded flash
          };

          // Flash vendor from word4[2:0].
          final flashVendorCode = (word4 >> 0) & 0x07;
          flashVendor = switch (flashVendorCode) {
            1 => 'XMC',
            2 => 'GD',
            3 => 'FM',
            4 => 'TT',
            5 => 'BY',
            _ => null,
          };

          // PSRAM capacity: psram_cap_hi from word5[19], psram_cap_low from
          // word4[4:3].
          final psramCapLow = (word4 >> 3) & 0x03;
          final psramCapHi = (word5 >> 19) & 0x01;
          final psramCap = (psramCapHi << 2) | psramCapLow;
          // Decode capacity in bytes and interface type.
          // 0=none,1=8MB OPI,2=2MB QSPI,3=16MB OPI,4=4MB QSPI
          switch (psramCap) {
            case 1:
              psramCapacityBytes = 8 * 1024 * 1024;
              psramType = 'OPI';
            case 2:
              psramCapacityBytes = 2 * 1024 * 1024;
              psramType = 'QSPI';
            case 3:
              psramCapacityBytes = 16 * 1024 * 1024;
              psramType = 'OPI';
            case 4:
              psramCapacityBytes = 4 * 1024 * 1024;
              psramType = 'QSPI';
          }

          // PSRAM vendor from word4[8:7].
          final psramVendorCode = (word4 >> 7) & 0x03;
          psramVendor = switch (psramVendorCode) {
            1 => 'AP_3v3',
            2 => 'AP_1v8',
            _ => null,
          };
        } catch (_) {
          // eFuse reads are best-effort; leave all fields null on error.
        }
      }

      return Success<EspChipInfo>(
        EspChipInfo(
          family: family,
          description: ChipFamilyResolver.describe(family),
          magicValue: magic,
          macAddress: macAddress,
          psramCapacityBytes: psramCapacityBytes,
          psramType: psramType,
          psramVendor: psramVendor,
          embeddedFlashBytes: embeddedFlashBytes,
          flashVendor: flashVendor,
          chipRevision: chipRevision,
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
    // Small inter-command delay so the ESP ROM bootloader has time to settle
    // between back-to-back register reads before the next command is sent.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return response.value;
  }

  Future<String> _readMacAddress(ChipFamily family) async {
    if (family == ChipFamily.esp32) {
      // Match esptool.py's ESP32 EFUSE flow. Some ESP32 ROM/USB-serial
      // combinations have been observed to return zero for the MAC words when
      // the BLK0 EFUSE cache is read immediately after chip detection; touching
      // another BLK0 word first mirrors esptool's feature/revision reads and
      // makes the following MAC word reads reliable.
      await _readRegister(_esp32EfuseMacPrimeRegister);
      final word2 = await _readRegister(_esp32EfuseMacWord2Register);
      final word1 = await _readRegister(_esp32EfuseMacWord1Register);
      final words = ByteData(8)
        ..setUint32(0, word2, Endian.big)
        ..setUint32(4, word1, Endian.big);
      final bytes = words.buffer.asUint8List().sublist(2, 8);
      if (bytes.any((byte) => byte != 0)) {
        return _formatMac(bytes);
      }
    }

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
    return _formatMac(bytes);
  }

  String _formatMac(List<int> bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }
}

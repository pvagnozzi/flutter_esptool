// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

/// Supported ESP ROM and stub command opcodes.
enum EspCommandOpcode {
  flashBegin(0x02),
  flashData(0x03),
  flashEnd(0x04),
  memBegin(0x05),
  memEnd(0x07),
  memData(0x06),
  sync(0x08),
  writeReg(0x09),
  readReg(0x0A),
  spiSetParams(0x0B),
  spiAttach(0x0D),
  changeBaud(0x0F),
  flashDeflBegin(0x10),
  flashDeflData(0x11),
  flashDeflEnd(0x12),
  flashMd5(0x13),
  getSecurityInfo(0x14),
  eraseFlash(0xD0),
  eraseRegion(0xD1);

  const EspCommandOpcode(this.value);

  /// The numeric opcode value.
  final int value;
}

/// Provides opcode parsing helpers.
extension EspCommandOpcodeParsing on EspCommandOpcode {
  /// Resolves an opcode from the numeric wire value.
  static EspCommandOpcode? fromValue(int value) {
    for (final opcode in EspCommandOpcode.values) {
      if (opcode.value == value) {
        return opcode;
      }
    }
    return null;
  }
}

/// Represents an ESP command request packet.
class EspCommand {
  /// Creates an [EspCommand].
  EspCommand({
    required this.opcode,
    Uint8List? data,
    int? checksum,
  })  : data = data ?? Uint8List(0),
        checksum = checksum ?? calculateChecksum(data ?? Uint8List(0));

  /// The command opcode.
  final EspCommandOpcode opcode;

  /// The request payload.
  final Uint8List data;

  /// The packet checksum.
  final int checksum;

  /// Calculates the ESP XOR checksum for a payload.
  static int calculateChecksum(Uint8List data) {
    var checksum = 0xEF;
    for (final byte in data) {
      checksum ^= byte;
    }
    return checksum & 0xFF;
  }
}

/// Represents an ESP response packet.
class EspResponse {
  /// Creates an [EspResponse].
  const EspResponse({
    required this.opcode,
    required this.value,
    required this.data,
    required this.status,
    required this.error,
  });

  /// The mirrored response opcode.
  final EspCommandOpcode opcode;

  /// The numeric response value field.
  final int value;

  /// The response data excluding status bytes.
  final Uint8List data;

  /// The ESP status code.
  final int status;

  /// The ESP error code.
  final int error;

  /// Whether the response reports success.
  bool get isSuccess => status == 0;
}

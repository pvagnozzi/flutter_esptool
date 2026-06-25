// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_esptool/src/infrastructure/partition/partition_entry.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';

/// Parses ESP partition tables.
class PartitionTable {
  /// The default partition table flash offset.
  static const int tableOffset = 0x8000;

  /// The size in bytes of a single table entry.
  static const int entrySize = 32;

  /// The first magic byte for a valid entry.
  static const int magic1 = 0xAA;

  /// The second magic byte for a valid entry.
  static const int magic2 = 0x50;

  /// Magic bytes of the MD5 checksum entry appended by esp-idf's
  /// gen_esp32part.py.  This entry terminates the table; it is not a
  /// partition entry and must be skipped rather than parsed.
  static const int md5Magic1 = 0xEB;
  static const int md5Magic2 = 0xEB;

  /// Parses a raw partition table buffer.
  static Result<List<PartitionEntry>> parse(Uint8List bytes) {
    try {
      if (bytes.length % entrySize != 0) {
        return const Failure<List<PartitionEntry>>(
          EspError(
            type: EspErrorType.invalidResponse,
            message: 'The partition table buffer length is not entry aligned',
          ),
        );
      }

      final entries = <PartitionEntry>[];
      for (var offset = 0; offset < bytes.length; offset += entrySize) {
        final chunk =
            Uint8List.fromList(bytes.sublist(offset, offset + entrySize));
        if (chunk.every((byte) => byte == 0xFF)) {
          continue;
        }
        // MD5 checksum entry (0xEB 0xEB) marks end of partition entries.
        if (chunk[0] == md5Magic1 && chunk[1] == md5Magic2) {
          break;
        }
        if (chunk[0] != magic1 || chunk[1] != magic2) {
          return const Failure<List<PartitionEntry>>(
            EspError(
              type: EspErrorType.invalidResponse,
              message:
                  'The partition table contains an entry with invalid magic bytes',
            ),
          );
        }

        final data = ByteData.sublistView(chunk);
        final labelBytes = chunk.sublist(12, 28);
        final label = ascii.decode(
          labelBytes.takeWhile((byte) => byte != 0).toList(growable: false),
        );
        entries.add(
          PartitionEntry(
            type: _typeFromByte(chunk[2]),
            subtype: _subtypeFromBytes(chunk[2], chunk[3]),
            offset: data.getUint32(4, Endian.little),
            size: data.getUint32(8, Endian.little),
            label: label,
            flags: data.getUint32(28, Endian.little),
          ),
        );
      }

      return Success<List<PartitionEntry>>(entries);
    } catch (error, stackTrace) {
      return Failure<List<PartitionEntry>>(
        EspError(
          type: EspErrorType.invalidResponse,
          message: error.toString(),
          stackTrace: stackTrace,
        ),
      );
    }
  }

  static PartitionType _typeFromByte(int value) {
    return switch (value) {
      0x00 => PartitionType.app,
      0x01 => PartitionType.data,
      _ => PartitionType.unknown,
    };
  }

  static PartitionSubtype _subtypeFromBytes(int type, int subtype) {
    if (type == 0x00) {
      return switch (subtype) {
        0x00 => PartitionSubtype.factory,
        0x10 => PartitionSubtype.ota0,
        0x11 => PartitionSubtype.ota1,
        _ => PartitionSubtype.unknown,
      };
    }

    if (type == 0x01) {
      return switch (subtype) {
        0x02 => PartitionSubtype.nvs,
        0x01 => PartitionSubtype.phy,
        0x03 => PartitionSubtype.coredump,
        0x82 => PartitionSubtype.spiffs,
        0x81 => PartitionSubtype.fat,
        _ => PartitionSubtype.unknown,
      };
    }

    return PartitionSubtype.unknown;
  }
}

// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/infrastructure/partition/partition_entry.dart';
import 'package:flutter_esptool/src/infrastructure/partition/partition_table.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PartitionTable', () {
    test('parses a valid single entry', () {
      final result = PartitionTable.parse(_buildEntry());
      expect(result, isA<Success<List<PartitionEntry>>>());
      final entries = (result as Success<List<PartitionEntry>>).value;
      expect(entries, hasLength(1));
      expect(entries.single.type, PartitionType.app);
      expect(entries.single.subtype, PartitionSubtype.factory);
      expect(entries.single.offset, 0x10000);
      expect(entries.single.size, 0x100000);
      expect(entries.single.label, 'factory');
    });

    test('returns an empty list for all-ff input', () {
      final result =
          PartitionTable.parse(Uint8List(32)..fillRange(0, 32, 0xFF));
      expect(result, isA<Success<List<PartitionEntry>>>());
      expect((result as Success<List<PartitionEntry>>).value, isEmpty);
    });

    test('returns failure for bad magic', () {
      final entry = _buildEntry();
      entry[0] = 0x00;
      final result = PartitionTable.parse(entry);
      expect(result, isA<Failure<List<PartitionEntry>>>());
    });

    test('reports encryption from flags', () {
      final entry = _buildEntry(flags: 0x01);
      final result = PartitionTable.parse(entry);
      final parsed = (result as Success<List<PartitionEntry>>).value.single;
      expect(parsed.isEncrypted, isTrue);
    });
  });
}

Uint8List _buildEntry({int flags = 0}) {
  final entry = Uint8List(32);
  entry[0] = 0xAA;
  entry[1] = 0x50;
  entry[2] = 0x00;
  entry[3] = 0x00;
  final data = ByteData.sublistView(entry);
  data.setUint32(4, 0x10000, Endian.little);
  data.setUint32(8, 0x100000, Endian.little);
  entry.setRange(12, 12 + 'factory'.length, 'factory'.codeUnits);
  data.setUint32(28, flags, Endian.little);
  return entry;
}

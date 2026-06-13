// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/transport/slip_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SlipCodec', () {
    test('encodes an empty payload', () {
      expect(SlipCodec.encode(Uint8List(0)), <int>[0xC0, 0xC0]);
    });

    test('encodes a simple payload', () {
      expect(
        SlipCodec.encode(Uint8List.fromList(<int>[0x01, 0x02])),
        <int>[0xC0, 0x01, 0x02, 0xC0],
      );
    });

    test('escapes delimiter bytes', () {
      expect(
        SlipCodec.encode(Uint8List.fromList(<int>[0xC0])),
        <int>[0xC0, 0xDB, 0xDC, 0xC0],
      );
    });

    test('escapes escape bytes', () {
      expect(
        SlipCodec.encode(Uint8List.fromList(<int>[0xDB])),
        <int>[0xC0, 0xDB, 0xDD, 0xC0],
      );
    });

    test('round-trips a payload through encode and decode', () {
      final payload = Uint8List.fromList(<int>[0x01, 0xC0, 0xDB, 0x02]);
      final decoded = SlipCodec.decode(SlipCodec.encode(payload));
      expect(decoded, isNotNull);
      expect(decoded, payload);
    });

    test('decodes multiple packets from one buffer', () {
      final first = SlipCodec.encode(Uint8List.fromList(<int>[0x01]));
      final second = SlipCodec.encode(Uint8List.fromList(<int>[0x02, 0x03]));
      final joined = Uint8List.fromList(<int>[...first, ...second]);

      final packets = SlipCodec.decodeMany(joined);
      expect(packets, hasLength(2));
      expect(packets[0], <int>[0x01]);
      expect(packets[1], <int>[0x02, 0x03]);
    });

    test('returns null for incomplete packets', () {
      expect(SlipCodec.decode(Uint8List.fromList(<int>[0xC0, 0x01])), isNull);
    });

    test('skips back-to-back empty packets in decodeMany', () {
      final packets = SlipCodec.decodeMany(
        Uint8List.fromList(<int>[0xC0, 0xC0, 0xC0, 0x01, 0xC0]),
      );
      expect(packets, hasLength(1));
      expect(packets.single, <int>[0x01]);
    });
  });
}

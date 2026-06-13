// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

/// Encodes and decodes ESP SLIP frames.
class SlipCodec {
  static const int _delimiter = 0xC0;
  static const int _escape = 0xDB;
  static const int _escapedDelimiter = 0xDC;
  static const int _escapedEscape = 0xDD;

  /// Encodes a payload into a SLIP frame.
  static Uint8List encode(Uint8List payload) {
    final bytes = BytesBuilder(copy: false);
    bytes.addByte(_delimiter);
    for (final byte in payload) {
      if (byte == _delimiter) {
        bytes.add(<int>[_escape, _escapedDelimiter]);
      } else if (byte == _escape) {
        bytes.add(<int>[_escape, _escapedEscape]);
      } else {
        bytes.addByte(byte);
      }
    }
    bytes.addByte(_delimiter);
    return bytes.toBytes();
  }

  /// Decodes a single SLIP frame or returns `null` for incomplete data.
  static Uint8List? decode(Uint8List raw) {
    if (raw.length < 2) {
      return null;
    }

    final start = raw.indexOf(_delimiter);
    if (start < 0) {
      return null;
    }

    final end = raw.lastIndexOf(_delimiter);
    if (end <= start) {
      return null;
    }

    final body = raw.sublist(start + 1, end);
    final bytes = BytesBuilder(copy: false);
    for (var index = 0; index < body.length; index++) {
      final byte = body[index];
      if (byte == _escape) {
        if (index + 1 >= body.length) {
          return null;
        }
        final escaped = body[++index];
        if (escaped == _escapedDelimiter) {
          bytes.addByte(_delimiter);
        } else if (escaped == _escapedEscape) {
          bytes.addByte(_escape);
        } else {
          return null;
        }
      } else {
        bytes.addByte(byte);
      }
    }

    return bytes.toBytes();
  }

  /// Decodes all complete non-empty SLIP frames from a buffer.
  static List<Uint8List> decodeMany(Uint8List buffer) {
    final packets = <Uint8List>[];
    var start = -1;

    for (var index = 0; index < buffer.length; index++) {
      if (buffer[index] != _delimiter) {
        continue;
      }

      if (start == -1) {
        start = index;
        continue;
      }

      final packet =
          decode(Uint8List.fromList(buffer.sublist(start, index + 1)));
      if (packet != null && packet.isNotEmpty) {
        packets.add(packet);
      }
      start = index;
    }

    return packets;
  }
}

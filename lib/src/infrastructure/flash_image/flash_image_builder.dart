// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

/// Builds flash-ready binary images.
class FlashImageBuilder {
  /// Pads [data] to [alignment] bytes using `0xFF` fill bytes.
  static Uint8List buildPaddedImage(Uint8List data, {int alignment = 4096}) {
    if (data.isEmpty || data.length % alignment == 0) {
      return Uint8List.fromList(data);
    }

    final paddedLength =
        ((data.length + alignment - 1) ~/ alignment) * alignment;
    final padded = Uint8List(paddedLength)..fillRange(0, paddedLength, 0xFF);
    padded.setRange(0, data.length, data);
    return padded;
  }

  /// Splits [data] into block records anchored at [offset].
  static List<({int offset, Uint8List data})> splitIntoBlocks(
    Uint8List data,
    int offset,
    int blockSize,
  ) {
    final blocks = <({int offset, Uint8List data})>[];
    var cursor = 0;
    while (cursor < data.length) {
      final end =
          cursor + blockSize > data.length ? data.length : cursor + blockSize;
      blocks.add((
        offset: offset + cursor,
        data: Uint8List.fromList(data.sublist(cursor, end)),
      ));
      cursor = end;
    }
    return blocks;
  }
}

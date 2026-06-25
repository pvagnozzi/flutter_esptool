// Debug multi-chunk read
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_esptool/flutter_esptool.dart';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? args[0] : 'COM22';
  stdout.writeln('Testing multi-chunk readFlashSlow on $port');

  for (var chunkIdx = 0; chunkIdx < 4; chunkIdx++) {
    final transport = EspTransport();
    final config = EspConfig(
      portName: port,
      initialBaudRate: 115200,
      timeout: const Duration(seconds: 8),
      syncRetries: 16,
    );

    try {
      final connection = ConnectionService(transport);
      final connectResult = await connection.connect(config);
      if (connectResult.isFailure) {
        stderr.writeln('Chunk $chunkIdx: connect failed');
        break;
      }

      final flash = FlashService(transport: transport);
      final offset = 0x8000 + chunkIdx * 64;
      stdout.writeln(
        'Reading chunk $chunkIdx from 0x${offset.toRadixString(16)}...',
      );

      final result = await flash.readFlash(
        FlashReadParameters(offset: offset, size: 64),
      );

      if (result.isSuccess) {
        final data = (result as Success<Uint8List>).value;
        final hex = data
            .sublist(0, 8)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(' ');
        stdout.writeln('Chunk $chunkIdx OK: first 8 bytes = $hex');
      } else {
        stderr.writeln(
          'Chunk $chunkIdx FAIL: ${(result as Failure<Uint8List>).error.message}',
        );
      }
    } catch (e) {
      stderr.writeln('Chunk $chunkIdx Exception: $e');
    } finally {
      await transport.close();
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }
  stdout.writeln('Done.');
}

// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:args/command_runner.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class WriteFlashCommand extends Command<void> {
  WriteFlashCommand() {
    argParser
      ..addOption('port', abbr: 'p', defaultsTo: 'COM1', help: 'Serial port device')
      ..addOption('address', abbr: 'a', defaultsTo: '0x1000', help: 'Start address')
      ..addOption('filename', abbr: 'f', help: 'Binary file to write')
      ..addOption('baud', abbr: 'b', defaultsTo: '115200', help: 'Baud rate')
      ..addFlag('verify', defaultsTo: true, help: 'Verify written data');
  }

  @override
  String get name => 'write_flash';

  @override
  String get description => 'Write binary to flash';

  @override
  FutureOr<void> run() async {
    final port = argResults?['port'] as String? ?? 'COM1';
    final address = int.tryParse((argResults?['address'] as String? ?? '0x1000').replaceFirst('0x', ''), radix: 16) ?? 0x1000;
    final filename = argResults?['filename'] as String?;
    final baud = int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;
    final verify = argResults?['verify'] as bool? ?? true;

    if (filename == null) {
      stderr.writeln('Error: --filename is required');
      exit(1);
    }

    final file = File(filename);
    if (!await file.exists()) {
      stderr.writeln('Error: File not found: $filename');
      exit(1);
    }

    final data = await file.readAsBytes();
    stdout.writeln('Writing ${data.length} bytes to 0x${address.toRadixString(16)}...');

    final config = EspConfig(
      portName: port,
      initialBaudRate: baud,
      timeout: const Duration(seconds: 5),
      syncRetries: 16,
    );
    final transport = EspTransport(serial: PlatformSerialPort(port));
    final flash = FlashService(transport: transport);

    try {
      final connection = ConnectionService(transport);
      await connection.connect(config);

      final result = await flash.writeFlash(
        FlashParameters(
          offset: address,
          data: data,
          verify: verify,
        ),
      );

      if (result.isFailure) {
        stderr.writeln('Failed to write: ${(result as Failure<void>).error.message}');
        exit(1);
      }

      stdout.writeln('Write complete!');
      await transport.close();
    } catch (e) {
      stderr.writeln('Error: $e');
      exit(1);
    }
  }
}

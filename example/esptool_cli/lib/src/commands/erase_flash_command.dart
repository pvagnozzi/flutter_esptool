// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class EraseFlashCommand extends Command<void> {
  EraseFlashCommand() {
    argParser
      ..addOption('port', abbr: 'p', defaultsTo: 'COM1', help: 'Serial port device')
      ..addOption('baud', abbr: 'b', defaultsTo: '115200', help: 'Baud rate');
  }

  @override
  String get name => 'erase_flash';

  @override
  String get description => 'Erase entire flash';

  @override
  FutureOr<void> run() async {
    final port = argResults?['port'] as String? ?? 'COM1';
    final baud = int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;

    stdout.writeln('Erasing flash...');

    final config = EspConfig(
     portName: port,
     initialBaudRate: baud,
     timeout: Duration(seconds: 5),
     syncRetries: 16,
    );
    final transport = EspTransport(serial: PlatformSerialPort(port));
    final flash = FlashService(transport: transport);

    try {
      final connection = ConnectionService(transport);
      await connection.connect(config);

      final result = await flash.eraseFlash();
      if (result.isFailure) {
        stderr.writeln('Failed to erase: ${(result as Failure<void>).error.message}');
        exit(1);
      }

      stdout.writeln('Erase complete!');
      await transport.close();
    } catch (e) {
      stderr.writeln('Error: $e');
      exit(1);
    }
  }
}

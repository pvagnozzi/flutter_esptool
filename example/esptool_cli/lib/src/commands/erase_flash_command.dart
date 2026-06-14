// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class EraseFlashCommand extends Command<void> {
  EraseFlashCommand() {
    argParser
      ..addOption(
        'port',
        abbr: 'p',
        mandatory: true,
        help: 'Serial port device (required)',
      )
      ..addOption('baud', abbr: 'b', defaultsTo: '115200', help: 'Baud rate');
  }

  @override
  String get name => 'erase_flash';

  @override
  String get description => 'Erase entire flash';

  @override
  FutureOr<void> run() async {
    final port = requirePort(this);
    final baud =
        int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;

    stdout.writeln('Erasing flash...');

    final config = EspConfig(
      portName: port,
      initialBaudRate: baud,
      timeout: const Duration(seconds: 5),
      syncRetries: 16,
    );
    final transport = EspTransport();
    final flash = FlashService(transport: transport);

    try {
      final connection = ConnectionService(transport);
      await connectOrExit(connection, config);

      final result = await flash.eraseFlash();
      if (result.isFailure) {
        stderr.writeln(
          'Failed to erase: ${(result as Failure<void>).error.message}',
        );
        exit(1);
      }

      stdout.writeln('Erase complete!');
    } catch (e) {
      stderr.writeln('Error: $e');
      exit(1);
    } finally {
      await transport.close();
    }
  }
}

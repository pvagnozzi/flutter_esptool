// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class EraseRegionCommand extends Command<void> {
  EraseRegionCommand() {
    argParser
      ..addOption(
        'port',
        abbr: 'p',
        mandatory: true,
        help: 'Serial port device (required)',
      )
      ..addOption('address', abbr: 'a', mandatory: true, help: 'Start address')
      ..addOption('length', abbr: 'l', mandatory: true, help: 'Length in bytes')
      ..addOption('baud', abbr: 'b', defaultsTo: '115200', help: 'Baud rate');
  }

  @override
  String get name => 'erase_region';

  @override
  String get description => 'Erase a region of flash';

  @override
  FutureOr<void> run() async {
    final port = requirePort(this);
    final address = parseFlexibleInt(
      argResults?['address'] as String? ?? '0x0',
      defaultValue: 0,
    );
    final length = parseFlexibleInt(
      argResults?['length'] as String? ?? '0x1000',
      defaultValue: 0x1000,
    );
    final baud =
        int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;

    stdout.writeln(
      'Erasing $length bytes at 0x${address.toRadixString(16)}...',
    );

    final config = EspConfig(
      portName: port,
      initialBaudRate: baud,
      timeout: const Duration(seconds: 10),
      syncRetries: 16,
    );
    final transport = EspTransport();
    final flash = FlashService(transport: transport);

    try {
      final connection = ConnectionService(transport);
      await connectOrExit(connection, config);

      final result = await flash.eraseFlash(offset: address, size: length);
      if (result.isFailure) {
        stderr.writeln(
          'Failed to erase region: ${(result as Failure<void>).error.message}',
        );
        exit(1);
      }

      stdout.writeln('Erase region complete!');
    } catch (e) {
      stderr.writeln('Error: $e');
      exit(1);
    } finally {
      await transport.close();
    }
  }
}

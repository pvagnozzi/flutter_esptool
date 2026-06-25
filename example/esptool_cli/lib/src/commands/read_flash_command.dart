// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class ReadFlashCommand extends Command<void> {
  ReadFlashCommand({
    EspTransportInterface Function()? transportFactory,
  }) : _transportFactory = transportFactory ?? createDefaultTransport {
    argParser
      ..addOption(
        'port',
        abbr: 'p',
        mandatory: true,
        help: 'Serial port device (required)',
      )
      ..addOption(
        'address',
        abbr: 'a',
        defaultsTo: '0x0',
        help: 'Start address',
      )
      ..addOption(
        'length',
        abbr: 'l',
        defaultsTo: '0x100',
        help: 'Length in bytes',
      )
      ..addOption('filename', abbr: 'f', help: 'Output filename')
      ..addOption('baud', abbr: 'b', defaultsTo: '115200', help: 'Baud rate')
      ..addOption(
        'timeout',
        abbr: 't',
        defaultsTo: '15',
        help: 'Timeout in seconds',
      );
  }

  final EspTransportInterface Function() _transportFactory;

  @override
  String get name => 'read_flash';

  @override
  String get description => 'Read binary from flash';

  @override
  FutureOr<void> run() async {
    final port = requirePort(this);
    final address = parseFlexibleInt(
      argResults?['address'] as String? ?? '0x0',
      defaultValue: 0,
    );
    final length = parseFlexibleInt(
      argResults?['length'] as String? ?? '0x100',
      defaultValue: 0x100,
    );
    final filename = argResults?['filename'] as String?;
    final baud =
        int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;
    final timeout =
        int.tryParse(argResults?['timeout'] as String? ?? '15') ?? 15;

    if (filename == null || filename.trim().isEmpty) {
      stderr.writeln('Error: --filename is required');
      exitCommand(1);
    }

    stdout.writeln(
      'Reading $length bytes from 0x${address.toRadixString(16)}...',
    );

    final config = EspConfig(
      portName: port,
      initialBaudRate: baud,
      timeout: Duration(seconds: timeout),
      syncRetries: 16,
    );
    final transport = _transportFactory();
    final flash = FlashService(transport: transport);

    try {
      final connection = ConnectionService(transport);
      await connectOrExit(connection, config);

      final result = await flash.readFlash(
        FlashReadParameters(offset: address, size: length),
      );
      if (result.isFailure) {
        stderr.writeln(
          'Failed to read flash: ${(result as Failure<Uint8List>).error.message}',
        );
        exitCommand(1);
      }

      final data = (result as Success<Uint8List>).value;
      await File(filename).writeAsBytes(data);
      stdout.writeln('Read complete! Wrote ${data.length} bytes to $filename');
    } catch (e) {
      stderr.writeln('Error: $e');
      exitCommand(1);
    } finally {
      await transport.close();
    }
  }
}

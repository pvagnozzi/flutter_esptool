// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class ChipIdCommand extends Command<void> {
  ChipIdCommand() {
    argParser
      ..addOption(
        'port',
        abbr: 'p',
        mandatory: true,
        help: 'Serial port device (required)',
      )
      ..addOption('baud', abbr: 'b', defaultsTo: '115200', help: 'Baud rate')
      ..addOption(
        'timeout',
        abbr: 't',
        defaultsTo: '10',
        help: 'Timeout in seconds',
      );
  }

  @override
  String get name => 'chip_id';

  @override
  String get description => 'Read chip ID and MAC address';

  @override
  FutureOr<void> run() async {
    final port = requirePort(this);
    final baud =
        int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;
    final timeout =
        int.tryParse(argResults?['timeout'] as String? ?? '10') ?? 10;

    stdout.writeln('Connecting to $port at $baud baud...');

    final config = EspConfig(
      portName: port,
      initialBaudRate: baud,
      timeout: Duration(seconds: timeout),
      syncRetries: 16,
    );

    final transport = EspTransport();

    try {
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);

      await connectOrExit(connection, config);

      final detectResult = await detection.detect();
      if (detectResult.isFailure) {
        stderr.writeln(
          'Failed to detect chip: ${(detectResult as Failure<EspChipInfo>).error.message}',
        );
        exit(1);
      }

      final chipInfo = (detectResult as Success<EspChipInfo>).value;
      stdout.writeln('Chip Description: ${chipInfo.description}');
      stdout.writeln(
        'Chip Magic: 0x${chipInfo.magicValue.toRadixString(16).padLeft(8, '0')}',
      );
      stdout.writeln('MAC Address: ${chipInfo.macAddress}');
    } catch (e) {
      stderr.writeln('Error: $e');
      exit(1);
    } finally {
      await transport.close();
    }
  }
}

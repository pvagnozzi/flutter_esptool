// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class ReadMacCommand extends Command<void> {
  ReadMacCommand({
    EspTransportInterface Function()? transportFactory,
  }) : _transportFactory = transportFactory ?? EspTransport.new {
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

  final EspTransportInterface Function() _transportFactory;

  @override
  String get name => 'read_mac';

  @override
  String get description => 'Read MAC address';

  @override
  FutureOr<void> run() async {
    final port = requirePort(this);
    final baud =
        int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;
    final timeout =
        int.tryParse(argResults?['timeout'] as String? ?? '10') ?? 10;

    final config = EspConfig(
      portName: port,
      initialBaudRate: baud,
      timeout: Duration(seconds: timeout),
      syncRetries: 16,
    );

    final transport = _transportFactory();

    try {
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);

      await connectOrExit(connection, config);
      final detectResult = await detection.detect();

      if (detectResult.isFailure) {
        stderr.writeln(
          'Failed to read MAC: ${(detectResult as Failure<EspChipInfo>).error.message}',
        );
        exitCommand(1);
      }

      final chipInfo = (detectResult as Success<EspChipInfo>).value;
      stdout.writeln('MAC Address: ${chipInfo.macAddress}');
    } catch (e) {
      stderr.writeln('Error: $e');
      exitCommand(1);
    } finally {
      await transport.close();
    }
  }
}

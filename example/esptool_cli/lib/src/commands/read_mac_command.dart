// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class ReadMacCommand extends Command<void> {
  ReadMacCommand() {
    argParser
      ..addOption('port', abbr: 'p', defaultsTo: 'COM1', help: 'Serial port device')
      ..addOption('baud', abbr: 'b', defaultsTo: '115200', help: 'Baud rate')
      ..addOption('timeout', abbr: 't', defaultsTo: '10', help: 'Timeout in seconds');
  }

  @override
  String get name => 'read_mac';

  @override
  String get description => 'Read MAC address';

  @override
  FutureOr<void> run() async {
    final port = argResults?['port'] as String? ?? 'COM1';
    final baud = int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;
    final timeout = int.tryParse(argResults?['timeout'] as String? ?? '10') ?? 10;

    final config = EspConfig(
      portName: port,
     initialBaudRate: baud,
      timeout: Duration(seconds: timeout),
     syncRetries: 16,
    );

    final transport = EspTransport(serial: PlatformSerialPort(port));

    try {
      final connection = ConnectionService(transport);
      final detection = ChipDetectionService(transport);

      await connection.connect(config);
      final detectResult = await detection.detect();

      if (detectResult.isFailure) {
        stderr.writeln('Failed to read MAC: ${(detectResult as Failure<EspChipInfo>).error.message}');
        exit(1);
      }

      final chipInfo = (detectResult as Success<EspChipInfo>).value;
      stdout.writeln('MAC Address: ${chipInfo.macAddress}');

      await transport.close();
    } catch (e) {
      stderr.writeln('Error: $e');
      exit(1);
    }
  }
}

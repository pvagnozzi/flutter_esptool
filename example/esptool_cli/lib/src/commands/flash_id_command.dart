// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class FlashIdCommand extends Command<void> {
  FlashIdCommand({
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
  String get name => 'flash_id';

  @override
  String get description => 'Read SPI flash ID';

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
    final info = InfoService(transport: transport);

    try {
      final connection = ConnectionService(transport);
      await connectOrExit(connection, config);

      final result = await info.getFlashId();
      if (result.isFailure) {
        stderr.writeln(
          'Failed to read flash ID: ${(result as Failure<EspFlashInfo>).error.message}',
        );
        exitCommand(1);
      }

      final flashInfo = (result as Success<EspFlashInfo>).value;
      final jedecId =
          (flashInfo.manufacturerId << 16) |
          (flashInfo.deviceId << 8) |
          flashInfo.capacityId;
      stdout.writeln(
        'Flash ID: 0x${jedecId.toRadixString(16).padLeft(6, '0')}',
      );
      stdout.writeln(
        'Manufacturer ID: 0x${flashInfo.manufacturerId.toRadixString(16).padLeft(2, '0')}',
      );
      if (flashInfo.manufacturerName != null) {
        stdout.writeln('Manufacturer: ${flashInfo.manufacturerName}');
      }
      stdout.writeln(
        'Device ID: 0x${flashInfo.deviceId.toRadixString(16).padLeft(2, '0')}',
      );
      stdout.writeln(
        'Capacity ID: 0x${flashInfo.capacityId.toRadixString(16).padLeft(2, '0')}',
      );
      if (flashInfo.capacityBytes != null) {
        stdout.writeln('Capacity: ${flashInfo.capacityBytes} bytes');
      }
    } catch (e) {
      stderr.writeln('Error: $e');
      exitCommand(1);
    } finally {
      await transport.close();
    }
  }
}

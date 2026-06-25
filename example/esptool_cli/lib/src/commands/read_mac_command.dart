// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class ReadMacCommand extends Command<void> {
  ReadMacCommand({EspTransportInterface Function()? transportFactory})
    : _transportFactory = transportFactory ?? createDefaultTransport {
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
  String get description => 'Read WiFi and BT MAC addresses';

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
          'Failed to read MAC: '
          '${(detectResult as Failure<EspChipInfo>).error.message}',
        );
        exitCommand(1);
      }

      final chipInfo = (detectResult as Success<EspChipInfo>).value;
      stdout.writeln('WiFi MAC Address: ${chipInfo.macAddress}');

      // BT MAC = WiFi MAC + 2 (applies to ESP32 family chips).
      // ESP8266 has no Bluetooth; skip for unknown family too.
      final btMac = _computeBtMac(chipInfo);
      if (btMac != null) {
        stdout.writeln('BT   MAC Address: $btMac');
      }
    } catch (e) {
      stderr.writeln('Error: $e');
      exitCommand(1);
    } finally {
      await transport.close();
    }
  }

  /// Returns the Bluetooth MAC for ESP32-family chips (WiFi MAC + 2),
  /// or null when BT is not applicable (ESP8266, unknown).
  static String? _computeBtMac(EspChipInfo chipInfo) {
    const btFamilies = {
      ChipFamily.esp32,
      ChipFamily.esp32s2,
      ChipFamily.esp32s3,
      ChipFamily.esp32c3,
    };
    if (!btFamilies.contains(chipInfo.family)) {
      return null;
    }

    final parts = chipInfo.macAddress.split(':');
    if (parts.length != 6) {
      return null;
    }

    // Treat the MAC as a 48-bit integer, add 2, split back to bytes.
    var mac48 = parts.fold<int>(0, (acc, hex) {
      return (acc << 8) | int.parse(hex, radix: 16);
    });
    mac48 = (mac48 + 2) & 0xFFFFFFFFFFFF;

    final btBytes = List.generate(6, (i) => (mac48 >> (8 * (5 - i))) & 0xFF);
    return btBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }
}

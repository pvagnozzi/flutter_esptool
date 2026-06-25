// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class ReadPartitionsCommand extends Command<void> {
  ReadPartitionsCommand({EspTransportInterface Function()? transportFactory})
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
        defaultsTo: '20',
        help: 'Timeout in seconds',
      );
  }

  final EspTransportInterface Function() _transportFactory;

  @override
  String get name => 'read_partitions';

  @override
  String get description => 'Read and display the ESP partition table';

  @override
  FutureOr<void> run() async {
    final port = requirePort(this);
    final baud =
        int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;
    final timeout =
        int.tryParse(argResults?['timeout'] as String? ?? '20') ?? 20;

    stdout.writeln('Reading partition table from $port...');

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

      // Partition table is at offset 0x8000, size 0xC00 (3 KB = up to 95 entries)
      const tableOffset = PartitionTable.tableOffset; // 0x8000
      const tableSize = 0xC00;

      final readResult = await flash.readFlash(
        const FlashReadParameters(offset: tableOffset, size: tableSize),
      );

      if (readResult.isFailure) {
        stderr.writeln(
          'Failed to read partition table: '
          '${(readResult as Failure<Uint8List>).error.message}',
        );
        exitCommand(1);
      }

      final rawBytes = (readResult as Success<Uint8List>).value;
      final parseResult = PartitionTable.parse(rawBytes);

      if (parseResult.isFailure) {
        stderr.writeln(
          'Failed to parse partition table: '
          '${(parseResult as Failure<List<PartitionEntry>>).error.message}',
        );
        exitCommand(1);
      }

      final entries = (parseResult as Success<List<PartitionEntry>>).value;

      if (entries.isEmpty) {
        stdout.writeln('No partition entries found (flash may be erased).');
        return;
      }

      stdout.writeln(
        '${'Label'.padRight(20)} ${'Type'.padRight(12)} '
        '${'Subtype'.padRight(12)} ${'Offset'.padRight(12)} '
        '${'Size'.padRight(12)} Encrypted',
      );
      stdout.writeln('-' * 80);

      for (final entry in entries) {
        final offsetHex = '0x${entry.offset.toRadixString(16).padLeft(8, '0')}';
        final sizeHex = '0x${entry.size.toRadixString(16).padLeft(8, '0')}';
        stdout.writeln(
          '${entry.label.padRight(20)} '
          '${entry.type.name.padRight(12)} '
          '${entry.subtype.name.padRight(12)} '
          '${offsetHex.padRight(12)} '
          '${sizeHex.padRight(12)} '
          '${entry.isEncrypted ? "yes" : "no"}',
        );
      }

      stdout.writeln('\nTotal: ${entries.length} partition(s)');
    } catch (e) {
      stderr.writeln('Error: $e');
      exitCommand(1);
    } finally {
      await transport.close();
    }
  }
}

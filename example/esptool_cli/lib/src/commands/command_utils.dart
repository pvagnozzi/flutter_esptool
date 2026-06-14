// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

String requirePort(Command<dynamic> command) {
  final results = command.argResults;
  if (results == null || !results.wasParsed('port')) {
    throw UsageException('Missing option "port".', command.usage);
  }

  final port = results['port'] as String?;
  if (port == null || port.trim().isEmpty) {
    throw UsageException('Missing option "port".', command.usage);
  }

  return port.trim();
}

int parseFlexibleInt(String value, {required int defaultValue}) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.startsWith('0x')) {
    return int.tryParse(trimmed.substring(2), radix: 16) ?? defaultValue;
  }
  return int.tryParse(trimmed) ?? defaultValue;
}

Future<void> connectOrExit(
  ConnectionService connection,
  EspConfig config,
) async {
  final result = await connection.connect(config);
  if (result.isFailure) {
    stderr.writeln(
      'Failed to connect: ${(result as Failure<void>).error.message}',
    );
    exit(1);
  }
}

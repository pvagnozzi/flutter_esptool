// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_esptool/flutter_esptool.dart';
import 'package:meta/meta.dart';

/// Exception used by tests when command termination is intercepted.
class CommandExit implements Exception {
  const CommandExit(this.code);

  final int code;
}

typedef CommandExitHandler = Never Function(int code);

CommandExitHandler _exitHandler = exit;

/// Allows tests to intercept command termination.
@visibleForTesting
void setExitHandlerForTesting(CommandExitHandler handler) {
  _exitHandler = handler;
}

/// Restores default process exit behavior.
@visibleForTesting
void resetExitHandlerForTesting() {
  _exitHandler = exit;
}

Never exitCommand(int code) => _exitHandler(code);

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
    exitCommand(1);
  }
}

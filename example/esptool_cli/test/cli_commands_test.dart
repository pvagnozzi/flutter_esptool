// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/chip_id_command.dart';
import 'package:esptool_cli/src/commands/flash_id_command.dart';
import 'package:esptool_cli/src/commands/read_mac_command.dart';
import 'package:esptool_cli/src/commands/version_command.dart';
import 'package:flutter_test/flutter_test.dart';

CommandRunner<void> _createRunner() {
  return CommandRunner<void>(
    'esptool',
    'A complete ESP chip programming tool (Dart clone of esptool.py)',
  )
    ..addCommand(VersionCommand())
    ..addCommand(ChipIdCommand())
    ..addCommand(ReadMacCommand())
    ..addCommand(FlashIdCommand());
}

void main() {
  group('esptool CLI commands', () {
    test('help shows available commands', () {
      final runner = _createRunner();
      final usage = runner.usage;

      expect(usage, contains('chip_id'));
      expect(usage, contains('read_mac'));
      expect(usage, contains('flash_id'));
      expect(usage, contains('version'));
    });

    test('hardware commands require an explicit --port', () async {
      final runner = _createRunner();

      await expectLater(
        runner.run(['chip_id']),
        throwsA(
          isA<UsageException>()
              .having((error) => error.message, 'message', contains('port'))
              .having((error) => error.usage, 'usage', contains('--port'))
              .having((error) => error.usage, 'usage', isNot(contains('COM1'))),
        ),
      );
    });
  });
}

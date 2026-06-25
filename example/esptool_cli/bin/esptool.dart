// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/chip_id_command.dart';
import 'package:esptool_cli/src/commands/erase_flash_command.dart';
import 'package:esptool_cli/src/commands/erase_region_command.dart';
import 'package:esptool_cli/src/commands/flash_id_command.dart';
import 'package:esptool_cli/src/commands/read_flash_command.dart';
import 'package:esptool_cli/src/commands/read_mac_command.dart';
import 'package:esptool_cli/src/commands/read_partitions_command.dart';
import 'package:esptool_cli/src/commands/version_command.dart';
import 'package:esptool_cli/src/commands/write_flash_command.dart';

Future<void> main(List<String> arguments) async {
  final runner =
      CommandRunner<void>(
          'esptool',
          'A complete ESP chip programming tool (Dart clone of esptool.py)',
        )
        ..addCommand(VersionCommand())
        ..addCommand(ChipIdCommand())
        ..addCommand(ReadMacCommand())
        ..addCommand(FlashIdCommand())
        ..addCommand(ReadFlashCommand())
        ..addCommand(ReadPartitionsCommand())
        ..addCommand(WriteFlashCommand())
        ..addCommand(EraseFlashCommand())
        ..addCommand(EraseRegionCommand());

  try {
    await runner.run(arguments);
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}

// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:esptool_cli/src/commands/command_utils.dart';

class ReadFlashCommand extends Command<void> {
  ReadFlashCommand() {
    argParser
      ..addOption('port', abbr: 'p', mandatory: true, help: 'Serial port device (required)')
      ..addOption('address', abbr: 'a', defaultsTo: '0x0', help: 'Start address')
      ..addOption('length', abbr: 'l', defaultsTo: '0x100', help: 'Length in bytes')
      ..addOption('filename', abbr: 'f', help: 'Output filename')
      ..addOption('baud', abbr: 'b', defaultsTo: '115200', help: 'Baud rate');
  }

  @override
  String get name => 'read_flash';

  @override
  String get description => 'Read binary from flash';

  @override
  FutureOr<void> run() async {
    requirePort(this);
    stderr.writeln('Error: read_flash requires stub loader support (not yet implemented)');
    exit(1);
  }
}

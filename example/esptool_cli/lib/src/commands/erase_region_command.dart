// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:flutter_esptool/flutter_esptool.dart';

class EraseRegionCommand extends Command<void> {
  EraseRegionCommand() {
    argParser
      ..addOption('port', abbr: 'p', defaultsTo: 'COM1', help: 'Serial port device')
      ..addOption('address', abbr: 'a', required: true, help: 'Start address')
      ..addOption('length', abbr: 'l', required: true, help: 'Length in bytes')
      ..addOption('baud', abbr: 'b', defaultsTo: '115200', help: 'Baud rate');
  }

  @override
  String get name => 'erase_region';

  @override
  String get description => 'Erase a region of flash';

  @override
  FutureOr<void> run() async {
    final port = argResults?['port'] as String? ?? 'COM1';
    final baud = int.tryParse(argResults?['baud'] as String? ?? '115200') ?? 115200;

    stderr.writeln('Error: erase_region requires stub loader support (not yet implemented)');
    exit(1);
  }
}

// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';

class VersionCommand extends Command<void> {
  @override
  String get name => 'version';

  @override
  String get description => 'Show esptool version';

  @override
  FutureOr<void> run() {
    stdout.writeln('esptool.dart v1.0.0 (Dart implementation)');
  }
}

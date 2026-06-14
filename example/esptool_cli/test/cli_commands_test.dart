// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('esptool CLI commands', () {
    test('version command prints version', () async {
      final result = await Process.run(
        'dart',
        ['bin/esptool.dart', 'version'],
        workingDirectory: '.',
      );

      expect(result.exitCode, equals(0));
      expect(result.stdout.toString(), contains('esptool'));
    });

    test('help shows available commands', () async {
      final result = await Process.run(
        'dart',
        ['bin/esptool.dart', '--help'],
        workingDirectory: '.',
      );

      expect(result.exitCode, equals(0));
      final output = result.stdout.toString();
      expect(output, contains('chip_id'));
      expect(output, contains('read_mac'));
    });
  });
}

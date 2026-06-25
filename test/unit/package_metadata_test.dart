import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pubspec metadata', () {
    late String pubspec;

    setUpAll(() {
      pubspec = File('pubspec.yaml').readAsStringSync();
    });

    test('uses latest platform_serial constraint', () {
      expect(pubspec, contains('platform_serial: ^0.1.2'));
    });

    test('contains canonical repository urls', () {
      expect(
        pubspec,
        contains('homepage: https://github.com/pvagnozzi/flutter_esptool'),
      );
      expect(
        pubspec,
        contains('repository: https://github.com/pvagnozzi/flutter_esptool'),
      );
      expect(
        pubspec,
        contains('issue_tracker: https://github.com/pvagnozzi/flutter_esptool/issues'),
      );
    });

    test('keeps a pub.dev-safe short description', () {
      final descriptionLine = pubspec
          .split('\n')
          .firstWhere((line) => line.trimLeft().startsWith('ESP8266/ESP32 serial'));
      expect(descriptionLine.length, lessThanOrEqualTo(180));
    });
  });
}

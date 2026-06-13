// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EspError', () {
    test('implements Exception', () {
      const error = EspError(type: EspErrorType.timeout, message: 'Boom');
      expect(error, isA<Exception>());
    });

    test('toString contains the type and message', () {
      const error = EspError(type: EspErrorType.timeout, message: 'Boom');
      expect(error.toString(), contains('EspErrorType.timeout'));
      expect(error.toString(), contains('Boom'));
    });

    test('error types are distinct', () {
      final values = EspErrorType.values.toSet();
      expect(values.length, EspErrorType.values.length);
    });
  });
}

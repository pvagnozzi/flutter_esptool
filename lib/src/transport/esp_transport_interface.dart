// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_config.dart';

/// Defines the transport contract used by ESP services.
abstract interface class EspTransportInterface {
  /// Opens the underlying serial connection with [config].
  Future<void> open(EspConfig config);

  /// Closes the underlying connection.
  Future<void> close();

  /// Sends [command] and returns the parsed response.
  Future<EspResponse> sendCommand(EspCommand command, {Duration? timeout});

  /// Requests a baud-rate change on the device.
  Future<void> changeBaud(int newBaud);

  /// Whether the transport is currently open.
  bool get isOpen;

  /// Resets the target into bootloader mode.
  Future<void> resetToBootloader();
}

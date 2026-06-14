// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_config.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/models/esp_result.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';
import 'package:platform_serial/platform_serial.dart';

/// Opens the transport and synchronizes with the ESP ROM bootloader.
class ConnectionService {
  /// Creates a [ConnectionService].
  ConnectionService(this._transport);

  final EspTransportInterface _transport;
  bool _isConnected = false;

  /// Whether the service currently considers the device connected.
  bool get isConnected => _isConnected;

  /// Connects to the ESP device with [config] and performs ROM sync.
  Future<Result<void>> connect(EspConfig config) async {
    try {
      await _transport.open(config);
      final syncTimeout = config.timeout;

      for (var attempt = 0; attempt < config.syncRetries; attempt++) {
        if (attempt > 0) {
          await _transport.resetToBootloader();
        }
        try {
          final response = await _transport.sendCommand(
            EspCommand(
              opcode: EspCommandOpcode.sync,
              data: _buildSyncPayload(),
              checksum: 0,
            ),
            timeout: syncTimeout,
          );
          if (response.isSuccess) {
            _isConnected = true;
            return const Success<void>(null);
          }
        } on EspError {
          // Keep retrying until the retry budget is exhausted.
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      await _transport.close();
      return const Failure<void>(
        EspError(
          type: EspErrorType.syncFailed,
          message: 'Failed to synchronize with the ESP bootloader',
        ),
      );
    } catch (error, stackTrace) {
      _isConnected = false;
      return Failure<void>(_mapError(error, stackTrace));
    }
  }

  /// Disconnects from the current device.
  Future<void> disconnect() async {
    await _transport.close();
    _isConnected = false;
  }

  Uint8List _buildSyncPayload() {
    final payload = Uint8List(36);
    payload.setRange(0, 4, <int>[0x07, 0x07, 0x12, 0x20]);
    payload.setRange(4, payload.length, List<int>.filled(32, 0x55));
    return payload;
  }

  EspError _mapError(Object error, StackTrace stackTrace) {
    if (error is EspError) {
      return error;
    }
    if (error is SerialError) {
      final type = switch (error.type) {
        SerialErrorType.portNotFound => EspErrorType.portUnavailable,
        SerialErrorType.timeout => EspErrorType.timeout,
        _ => EspErrorType.connectionFailed,
      };
      return EspError(
          type: type, message: error.message, stackTrace: stackTrace);
    }
    return EspError(
      type: EspErrorType.connectionFailed,
      message: error.toString(),
      stackTrace: stackTrace,
    );
  }
}

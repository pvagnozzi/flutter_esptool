// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_config.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';
import 'package:flutter_esptool/src/transport/slip_codec.dart';
import 'package:platform_serial/platform_serial.dart';

/// Serial transport implementation for the ESP SLIP protocol.
class EspTransport implements EspTransportInterface {
  /// Creates an [EspTransport].
  EspTransport({SerialPortInterface? serial})
      : serial = serial ?? SerialManager().createPort();

  /// The wrapped serial port implementation.
  final SerialPortInterface serial;

  EspConfig? _config;
  final BytesBuilder _readBuffer = BytesBuilder(copy: false);

  @override
  bool get isOpen => serial.isOpen;

  @override
  Future<void> open(EspConfig config) async {
    final serialConfig = SerialConfig(
      portName: config.portName,
      baudRate: config.initialBaudRate,
      dataBits: 8,
      stopBits: SerialStopBits.one,
      parity: SerialParity.none,
      flowControl: SerialFlowControl.none,
      readTimeout: config.timeout,
      writeTimeout: config.timeout,
    );

    await serial.open(serialConfig);
    await serial.resetBuffers();
    _config = config;
  }

  @override
  Future<void> close() async {
    if (!serial.isOpen) {
      return;
    }
    await serial.close();
    _config = null;
    _readBuffer.clear();
  }

  @override
  Future<void> resetToBootloader() async {
    if (!serial.isOpen) {
      throw const EspError(
        type: EspErrorType.connectionFailed,
        message: 'Serial port is not open',
      );
    }

    try {
      // Mirrors esptool's auto-reset sequence for ESP32-class boards.
      await serial.setDtr(false);
      await serial.setRts(true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await serial.setDtr(true);
      await serial.setRts(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await serial.setDtr(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } on SerialError catch (error) {
      if (error.type != SerialErrorType.platformUnavailable) {
        rethrow;
      }
      for (var index = 0; index < 4; index++) {
        await serial.write(Uint8List(0), timeout: _config?.timeout);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    await serial.flush();
  }

  @override
  Future<EspResponse> sendCommand(
    EspCommand command, {
    Duration? timeout,
  }) async {
    final effectiveTimeout =
        timeout ?? _config?.timeout ?? const Duration(seconds: 3);
    final packet = _buildPacket(command);
    final frame = SlipCodec.encode(packet);

    try {
      await serial.write(frame, timeout: effectiveTimeout);
      await serial.flush();
    } on SerialError catch (error, stackTrace) {
      throw _mapSerialError(error, stackTrace);
    }

    final responseFrame = await _readFrame(effectiveTimeout);
    return _parseResponse(responseFrame);
  }

  @override
  Future<void> changeBaud(int newBaud) async {
    final payload = Uint8List(8);
    final data = ByteData.sublistView(payload);
    data.setUint32(0, newBaud, Endian.little);
    data.setUint32(4, 0, Endian.little);

    final response = await sendCommand(
      EspCommand(opcode: EspCommandOpcode.changeBaud, data: payload),
      timeout: _config?.timeout,
    );

    if (!response.isSuccess) {
      throw const EspError(
        type: EspErrorType.badBaudRate,
        message: 'The device rejected the baud-rate change request',
      );
    }

    final config = _config;
    if (config != null) {
      _config = config.copyWith(flashBaudRate: newBaud);
    }
  }

  Uint8List _buildPacket(EspCommand command) {
    final packet = Uint8List(8 + command.data.length);
    final data = ByteData.sublistView(packet);
    data.setUint8(0, 0x00);
    data.setUint8(1, command.opcode.value);
    data.setUint16(2, command.data.length, Endian.little);
    data.setUint32(4, command.checksum, Endian.little);
    packet.setRange(8, packet.length, command.data);
    return packet;
  }

  Future<Uint8List> _readFrame(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final existing = _tryExtractFrame();
      if (existing != null) {
        return existing;
      }

      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }

      try {
        final chunk = await serial.read(1024, timeout: remaining);
        if (chunk.isNotEmpty) {
          _readBuffer.add(chunk);
        }
      } on SerialError catch (error, stackTrace) {
        if (error.type != SerialErrorType.timeout) {
          throw _mapSerialError(error, stackTrace);
        }
      }
    }

    final trailing = _readBuffer.toBytes();
    _readBuffer.clear();
    if (trailing.isNotEmpty) {
      throw const EspError(
        type: EspErrorType.partialPacket,
        message: 'A complete SLIP frame was not received before timeout',
      );
    }

    throw const EspError(
      type: EspErrorType.timeout,
      message: 'Timed out waiting for an ESP response',
    );
  }

  Uint8List? _tryExtractFrame() {
    final current = _readBuffer.toBytes();
    if (current.isEmpty) {
      return null;
    }

    final start = current.indexOf(0xC0);
    if (start < 0) {
      _readBuffer.clear();
      return null;
    }

    for (var index = start + 1; index < current.length; index++) {
      if (current[index] != 0xC0) {
        continue;
      }

      final rawFrame = Uint8List.fromList(current.sublist(start, index + 1));
      final frame = SlipCodec.decode(rawFrame);
      final remaining = Uint8List.fromList(current.sublist(index + 1));
      _readBuffer.clear();
      if (remaining.isNotEmpty) {
        _readBuffer.add(remaining);
      }
      if (frame == null || frame.isEmpty) {
        return null;
      }
      return frame;
    }

    if (start > 0) {
      _readBuffer.clear();
      _readBuffer.add(current.sublist(start));
    }
    return null;
  }

  EspResponse _parseResponse(Uint8List frame) {
    if (frame.length < 10) {
      throw const EspError(
        type: EspErrorType.invalidResponse,
        message: 'ESP response packet is too short',
      );
    }

    final data = ByteData.sublistView(frame);
    if (data.getUint8(0) != 0x01) {
      throw const EspError(
        type: EspErrorType.invalidResponse,
        message: 'ESP response packet has an invalid direction byte',
      );
    }

    final opcodeValue = data.getUint8(1);
    final opcode = EspCommandOpcodeParsing.fromValue(opcodeValue);
    if (opcode == null) {
      throw EspError(
        type: EspErrorType.invalidResponse,
        message:
            'Unsupported response opcode 0x${opcodeValue.toRadixString(16)}',
      );
    }

    final payload = frame.sublist(8);
    if (payload.length < 2) {
      throw const EspError(
        type: EspErrorType.invalidResponse,
        message: 'ESP response payload is missing status bytes',
      );
    }

    return EspResponse(
      opcode: opcode,
      value: data.getUint32(4, Endian.little),
      data: Uint8List.fromList(payload.sublist(0, payload.length - 2)),
      status: payload[payload.length - 2],
      error: payload[payload.length - 1],
    );
  }

  EspError _mapSerialError(SerialError error, StackTrace stackTrace) {
    final type = switch (error.type) {
      SerialErrorType.portNotFound => EspErrorType.portUnavailable,
      SerialErrorType.timeout => EspErrorType.timeout,
      _ => EspErrorType.connectionFailed,
    };
    return EspError(type: type, message: error.message, stackTrace: stackTrace);
  }
}

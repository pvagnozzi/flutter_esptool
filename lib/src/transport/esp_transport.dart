// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_config.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';
import 'package:flutter_esptool/src/transport/slip_codec.dart';
import 'package:platform_serial/platform_serial.dart';

/// Log event type emitted by [EspTransport].
enum EspTransportLogType {
  /// A command was sent to the device.
  commandSent,

  /// A response was received from the device.
  responseReceived,

  /// A transport-level error or diagnostic event.
  transportError,
}

/// Structured log entry emitted by [EspTransport].
class EspTransportLogEntry {
  /// Creates an [EspTransportLogEntry].
  const EspTransportLogEntry({
    required this.type,
    required this.timestamp,
    this.opcode,
    this.rawPacket,
    this.rawFrame,
    this.command,
    this.response,
    this.message,
  });

  /// The event type.
  final EspTransportLogType type;

  /// Event creation time.
  final DateTime timestamp;

  /// The command opcode associated with the event, if available.
  final EspCommandOpcode? opcode;

  /// ESP packet bytes (not SLIP-encoded), when available.
  final Uint8List? rawPacket;

  /// SLIP frame bytes, when available.
  final Uint8List? rawFrame;

  /// Decoded command, when available.
  final EspCommand? command;

  /// Decoded response, when available.
  final EspResponse? response;

  /// Error or diagnostic message, when available.
  final String? message;
}

/// Callback used to consume [EspTransport] structured logs.
typedef EspTransportLogger = void Function(EspTransportLogEntry entry);

/// Serial transport implementation for the ESP SLIP protocol.
class EspTransport implements EspTransportInterface {
  /// Creates an [EspTransport].
  EspTransport({SerialPortInterface? serial, this.logger})
      : serial = serial ?? SerialManager().createPort();

  /// The wrapped serial port implementation.
  final SerialPortInterface serial;

  /// Optional structured logger for command/response traffic.
  final EspTransportLogger? logger;

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
    _readBuffer
        .clear(); // discard any stale in-memory data from a previous session
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
      var dtrState = false;
      Future<void> setDtr(bool value) async {
        dtrState = value;
        await serial.setDtr(value);
      }

      Future<void> setRts(bool value) async {
        await serial.setRts(value);
        // Mirrors esptool workaround for some Windows drivers where
        // RTS changes are propagated reliably only when DTR is resent.
        await serial.setDtr(dtrState);
      }

      // Classic reset (esptool ClassicReset).
      await setDtr(false);
      await setRts(true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await setDtr(true);
      await setRts(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await setDtr(false);
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
    // Flush the hardware receive buffer and the in-memory read buffer so
    // that boot-loader messages emitted during the reset pulse do not
    // contaminate the next SYNC attempt.
    try {
      await serial.resetBuffers();
    } on SerialError {
      // Best-effort: ignore if the driver does not support it.
    }
    _readBuffer.clear();
  }

  @override
  Future<EspResponse> sendCommand(
    EspCommand command, {
    Duration? timeout,
  }) async {
    final effectiveTimeout =
        timeout ?? _config?.timeout ?? const Duration(seconds: 3);
    final deadline = DateTime.now().add(effectiveTimeout);
    final packet = _buildPacket(command);
    final frame = SlipCodec.encode(packet);
    logger?.call(
      EspTransportLogEntry(
        type: EspTransportLogType.commandSent,
        timestamp: DateTime.now(),
        opcode: command.opcode,
        rawPacket: Uint8List.fromList(packet),
        rawFrame: Uint8List.fromList(frame),
        command: command,
      ),
    );

    try {
      await serial.write(frame, timeout: effectiveTimeout);
      await serial.flush();
    } on SerialError catch (error, stackTrace) {
      final mapped = _mapSerialError(error, stackTrace);
      logger?.call(
        EspTransportLogEntry(
          type: EspTransportLogType.transportError,
          timestamp: DateTime.now(),
          opcode: command.opcode,
          command: command,
          message: mapped.message,
        ),
      );
      throw mapped;
    }

    try {
      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          break;
        }

        final responseFrame = await _readFrame(remaining);

        // Parse the frame, but treat malformed frames (too-short, invalid
        // direction, unknown opcode) as noise: log them and keep reading
        // rather than aborting the whole command.
        EspResponse response;
        try {
          response = _parseResponse(responseFrame.packet);
        } on EspError catch (parseError) {
          logger?.call(
            EspTransportLogEntry(
              type: EspTransportLogType.transportError,
              timestamp: DateTime.now(),
              opcode: command.opcode,
              rawPacket: Uint8List.fromList(responseFrame.packet),
              rawFrame: Uint8List.fromList(responseFrame.rawFrame),
              command: command,
              message: 'Noise frame skipped: ${parseError.message}',
            ),
          );
          continue;
        }

        logger?.call(
          EspTransportLogEntry(
            type: EspTransportLogType.responseReceived,
            timestamp: DateTime.now(),
            opcode: response.opcode,
            rawPacket: Uint8List.fromList(responseFrame.packet),
            rawFrame: Uint8List.fromList(responseFrame.rawFrame),
            command: command,
            response: response,
          ),
        );

        // ESP ROM can return stale/extra packets (for example extra SYNC replies).
        // Keep reading until the response opcode matches the in-flight command.
        if (response.opcode == command.opcode) {
          return response;
        }
      }

      throw const EspError(
        type: EspErrorType.timeout,
        message: 'Response opcode did not match the requested command',
      );
    } on EspError catch (error) {
      logger?.call(
        EspTransportLogEntry(
          type: EspTransportLogType.transportError,
          timestamp: DateTime.now(),
          opcode: command.opcode,
          command: command,
          message: error.message,
        ),
      );
      rethrow;
    }
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

  Future<_FrameReadResult> _readFrame(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      // Catch invalid-SLIP errors from _tryExtractFrame and treat them as
      // noise: discard the bad frame and keep reading from the wire.
      _FrameReadResult? existing;
      try {
        existing = _tryExtractFrame();
      } on EspError catch (frameError) {
        logger?.call(
          EspTransportLogEntry(
            type: EspTransportLogType.transportError,
            timestamp: DateTime.now(),
            message: 'Discarding invalid SLIP frame: ${frameError.message}',
          ),
        );
        _readBuffer.clear();
        continue;
      }
      if (existing != null) {
        return existing;
      }

      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }

      try {
        final available = await serial.bytesAvailable();
        final readLength = available > 0 ? available : 1;
        final chunk = await serial.read(readLength, timeout: remaining);
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

  _FrameReadResult? _tryExtractFrame() {
    final current = _readBuffer.toBytes();
    if (current.isEmpty) {
      return null;
    }

    // Skip leading 0xC0 flush bytes that some ROM/stub implementations emit
    // before each frame.  Standard SLIP uses a single 0xC0 as start delimiter
    // but the ESP ROM may prepend an extra 0xC0 as a buffer-flush indicator.
    // We advance `start` past any consecutive 0xC0 bytes so that we treat the
    // LAST of the cluster as the real opening delimiter.
    var start = current.indexOf(0xC0);
    if (start < 0) {
      _readBuffer.clear();
      return null;
    }
    while (start + 1 < current.length && current[start + 1] == 0xC0) {
      start++;
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
      if (frame == null) {
        throw const EspError(
          type: EspErrorType.invalidResponse,
          message: 'Received an invalid SLIP frame',
        );
      }
      if (frame.isEmpty) {
        // Empty frame (bare 0xC0 pair): skip it and re-scan the remaining
        // buffer in the same call rather than returning null and waiting for
        // a serial-read round-trip.
        return _tryExtractFrame();
      }
      return _FrameReadResult(
        rawFrame: rawFrame,
        packet: frame,
      );
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

class _FrameReadResult {
  const _FrameReadResult({
    required this.rawFrame,
    required this.packet,
  });

  final Uint8List rawFrame;
  final Uint8List packet;
}

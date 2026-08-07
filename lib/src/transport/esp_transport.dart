// Copyright (c) 2026 Piergiorgio Vagnozzi
// Licensed under the MIT License.

import 'dart:typed_data';

import 'package:flutter_esptool/src/models/esp_command.dart';
import 'package:flutter_esptool/src/models/esp_config.dart';
import 'package:flutter_esptool/src/models/esp_error.dart';
import 'package:flutter_esptool/src/transport/esp_transport_interface.dart';
import 'package:flutter_esptool/src/transport/slip_codec.dart';
import 'package:platform_serial/platform_serial.dart';

void _d(String msg) {
  // ignore: avoid_print
  print('${DateTime.now().toIso8601String()} $msg');
}

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
  ///
  /// Uses [DirectSerialPort] by default instead of [SerialPort].  [SerialPort]
  /// starts a 40 ms background polling timer that races against explicit
  /// [serial.read] calls and steals bytes from the SLIP framing loop.
  /// [DirectSerialPort] has no background stream, so all reads go directly to
  /// the platform layer.
  EspTransport({SerialPortInterface? serial, this.logger})
      : serial = serial ?? DirectSerialPort();

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

    _d('[ESP] open: calling serial.open ${config.portName}');
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

      _d('[ESP] resetToBootloader mode=${_config?.resetMode}');
      if (_config?.resetMode == EspResetMode.none) {
        // No reset — device is assumed to already be in bootloader mode.
        // Just flush buffers below and return.
      } else if (_config?.resetMode == EspResetMode.usbJtag) {
        // USB JTAG/Serial reset (esptool USBJTAGSerialReset).
        // Used for ESP32-S2/S3/C3/C6/H2 chips with built-in USB peripheral
        // (Espressif VID 0x303a).  After this sequence the USB device
        // disconnects and re-enumerates — we close, wait, then reopen.
        await setRts(false);
        await setDtr(false); // Idle
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await setDtr(true); // Set IO0 low
        await setRts(false);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await setRts(true); // EN low — reset. Go through (1,1) not (0,0).
        await setDtr(false);
        await setRts(true); // Propagate RTS on Windows
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await setDtr(false);
        await setRts(false); // Chip out of reset, IO0 high → bootloader

        // The USB device disconnects during reset and re-enumerates as a
        // bootloader. Close the port, wait for re-enumeration, then reopen
        // with retries — the port may not be available immediately.
        final config = _config!;
        _d('[ESP] USB JTAG: closing port for re-enum');
        await serial.close();
        _d('[ESP] USB JTAG: waiting 1500ms for re-enum');
        await Future<void>.delayed(const Duration(milliseconds: 1500));
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
        SerialError? lastError;
        for (var attempt = 0; attempt < 10; attempt++) {
          try {
            _d('[ESP] USB JTAG: reopening port ${config.portName} attempt=${attempt + 1}');
            await serial.open(serialConfig);
            lastError = null;
            break;
          } on SerialError catch (e) {
            lastError = e;
            _d('[ESP] USB JTAG: reopen failed (${e.message}), retrying...');
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
        if (lastError != null) {
          throw lastError;
        }
        // Flush both the hardware RX buffer (which may contain ROM banner bytes
        // that accumulated during the 1500 ms re-enumeration wait) and the
        // in-memory read buffer.  Without this, stale ROM banner bytes remain
        // in the kernel buffer and contaminate subsequent SLIP frame reads.
        try {
          await serial.resetBuffers();
        } on SerialError {
          // Best-effort: ignore if the driver does not support it.
        }
        _readBuffer.clear();
        _d('[ESP] USB JTAG: port reopened OK');
        return; // buffers flushed — skip the generic flush/resetBuffers below
      } else {
        // Classic reset (esptool ClassicReset).
        await setDtr(false);
        await setRts(true);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await setDtr(true);
        await setRts(false);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await setDtr(false);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } on SerialError catch (error) {
      if (error.type != SerialErrorType.platformUnavailable) {
        rethrow;
      }
      for (var index = 0; index < 4; index++) {
        await serial.write(Uint8List(0), timeout: _config?.timeout);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    // Do NOT call serial.flush() here — on macOS it calls tcdrain() which
    // blocks the isolate until all bytes drain at hardware level.  The DTR/RTS
    // pin toggles above are fire-and-forget; there is nothing in the TX buffer
    // that needs draining.
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
      _d('[ESP] write ${frame.length} bytes opcode=${command.opcode}: '
          '${frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      await serial.write(frame, timeout: effectiveTimeout);
      _d('[ESP] write done');
      // Do NOT call serial.flush() here — on macOS it calls tcdrain() which
      // blocks the isolate until all bytes have been transmitted at the hardware
      // level. Our non-blocking write already hands bytes to the kernel buffer;
      // USB CDC/ACM flushes automatically at full USB bandwidth.
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
      // Noise frames (complete SLIP frames that fail to parse as a response for
      // the in-flight command) are set aside here rather than pushed straight
      // back into _readBuffer.  Pushing them back mid-loop caused an infinite
      // re-scan: _tryExtractFrame would re-extract the very same frame on the
      // next iteration without ever reading new bytes from the wire, so the
      // real response (arriving *after* the noise, e.g. a stub READ_FLASH MD5
      // digest that leaked past the previous command) was never read and the
      // command timed out.  On timeout we restore the noise so a subsequent
      // readRaw() can still retrieve it (needed for stub OHAI detection); on a
      // successful match we discard it as stale.
      final setAsideNoise = <int>[];
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
          // A ROM-rejection error (opcode=0x00 response) is a definitive
          // failure — re-raise it immediately rather than treating as noise.
          if (parseError.message.startsWith('ROM bootloader rejected')) {
            _d('[ESP] ROM rejected command ${command.opcode}: ${parseError.message}');
            rethrow;
          }
          // A short frame that does not look like an ESP response may be the
          // stub OHAI greeting (c0 4f 48 41 49 c0).  Set the raw frame aside so
          // that, if this command ultimately times out, it can be restored to
          // _readBuffer for a subsequent readRaw() to retrieve — but do NOT
          // push it back now, which would re-scan it forever.
          _d('[ESP] Noise frame (${responseFrame.packet.length}B), setting raw '
              'frame aside: '
              '${responseFrame.rawFrame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          setAsideNoise.addAll(responseFrame.rawFrame);
          logger?.call(
            EspTransportLogEntry(
              type: EspTransportLogType.transportError,
              timestamp: DateTime.now(),
              opcode: command.opcode,
              rawPacket: Uint8List.fromList(responseFrame.packet),
              rawFrame: Uint8List.fromList(responseFrame.rawFrame),
              command: command,
              message: 'Noise frame set aside: ${parseError.message}',
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
        _d('[ESP] frame opcode=${response.opcode} want=${command.opcode} '
            'value=0x${response.value.toRadixString(16)} '
            'status=${response.status} error=${response.error}');
        if (response.opcode == command.opcode) {
          _d('[ESP] opcode matched — returning response');
          // Discard any set-aside noise: it preceded the valid response and is
          // stale (e.g. a leaked stub digest frame) — restoring it would poison
          // the next command.
          return response;
        }
      }

      // Timed out without a matching response.  Restore any set-aside noise so
      // that a subsequent readRaw() can still retrieve it (stub OHAI greeting).
      if (setAsideNoise.isNotEmpty) {
        _readBuffer.add(Uint8List.fromList(setAsideNoise));
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
  Future<List<int>> readRaw(int count, {Duration? timeout}) async {
    final effectiveTimeout =
        timeout ?? _config?.timeout ?? const Duration(seconds: 5);
    final deadline = DateTime.now().add(effectiveTimeout);
    final result = <int>[];

    // Drain any bytes already sitting in the in-memory read buffer first.
    if (_readBuffer.length > 0) {
      final buffered = _readBuffer.toBytes();
      _readBuffer.clear();
      if (buffered.length >= count) {
        // Keep only the requested bytes and PRESERVE the remainder for the
        // next read.  The previous implementation discarded everything beyond
        // [count], silently dropping streamed data (e.g. stub READ_FLASH
        // packets that piled into the buffer while an earlier sendCommand was
        // still parsing its response frame).
        _readBuffer.add(buffered.sublist(count));
        return buffered.sublist(0, count);
      }
      result.addAll(buffered);
    }

    while (result.length < count && DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) break;
      try {
        final need = count - result.length;
        final available = await serial.bytesAvailable();
        final toRead = available > 0 ? available.clamp(1, need) : 1;
        _d('[ESP] readRaw: FIONREAD=$available toRead=$toRead'
            ' remaining=${remaining.inMilliseconds}ms');
        final chunk = await serial.read(toRead, timeout: remaining);
        _d('[ESP] readRaw: got ${chunk.length} bytes');
        if (chunk.isNotEmpty) {
          result.addAll(chunk.take(need));
        } else {
          // No data yet — yield to the event loop to avoid a tight spin.
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      } on SerialError catch (e) {
        if (e.type != SerialErrorType.timeout) {
          throw _mapSerialError(e, StackTrace.current);
        }
        await Future<void>.delayed(Duration.zero);
      }
    }

    return result;
  }

  @override
  Future<void> flushRx() async {
    _readBuffer.clear();
    try {
      await serial.resetBuffers();
    } on SerialError {
      // Best-effort.
    }
  }

  @override
  Future<void> writeRaw(List<int> bytes, {Duration? timeout}) async {
    final effectiveTimeout =
        timeout ?? _config?.timeout ?? const Duration(seconds: 5);
    try {
      await serial.write(
        Uint8List.fromList(bytes),
        timeout: effectiveTimeout,
      );
    } on SerialError catch (error, stackTrace) {
      throw _mapSerialError(error, stackTrace);
    }
  }

  @override
  Future<void> reopenPort({
    Duration waitBefore = const Duration(milliseconds: 1500),
  }) async {
    final config = _config;
    if (config == null) {
      _d('[ESP] reopenPort: no config — skipping');
      return;
    }
    _d('[ESP] reopenPort: closing port for stub USB re-enum');
    if (serial.isOpen) {
      try {
        await serial.close();
      } on SerialError {
        // Best-effort close.
      }
    }
    _readBuffer.clear();
    _d('[ESP] reopenPort: waiting ${waitBefore.inMilliseconds}ms for re-enum');
    await Future<void>.delayed(waitBefore);

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
    SerialError? lastError;
    for (var attempt = 0; attempt < 10; attempt++) {
      try {
        _d('[ESP] reopenPort: reopening ${config.portName} attempt=${attempt + 1}');
        await serial.open(serialConfig);
        lastError = null;
        break;
      } on SerialError catch (e) {
        lastError = e;
        _d('[ESP] reopenPort: reopen failed (${e.message}), retrying...');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    if (lastError != null) {
      throw _mapSerialError(lastError, StackTrace.current);
    }
    try {
      await serial.resetBuffers();
    } on SerialError {
      // Best-effort.
    }
    _readBuffer.clear();
    _d('[ESP] reopenPort: port reopened OK');
  }

  @override
  Future<void> hardReset() async {
    // The ESP32-S3 ROM always reboots after FLASH_END regardless of the
    // reboot flag, so by the time hardReset() is called the device is already
    // running user code and the ROM bootloader is no longer listening.
    // We therefore skip the writeReg round-trip entirely (it would time out)
    // and just pulse RTS to drive the EN line, which re-enters the app.
    // If the port is already closed (device re-enumerated), reopen it briefly
    // just to drive the RTS pin, then close again.
    _d('[ESP] hardReset: pulsing RTS (EN line) LOW then HIGH');

    final needsOpen = !serial.isOpen;
    if (needsOpen) {
      final config = _config;
      if (config == null) {
        // No config — cannot reopen. Just return; device already rebooted.
        _d('[ESP] hardReset: no config, skipping RTS pulse');
        return;
      }
      try {
        final serialConfig = SerialConfig(
          portName: config.portName,
          baudRate: config.initialBaudRate,
          dataBits: 8,
          stopBits: SerialStopBits.one,
          parity: SerialParity.none,
          flowControl: SerialFlowControl.none,
          readTimeout: const Duration(seconds: 1),
          writeTimeout: const Duration(seconds: 1),
        );
        await serial.open(serialConfig);
      } on SerialError {
        // Port not yet available after re-enum — device already booted, skip.
        _d('[ESP] hardReset: port unavailable, skipping RTS pulse');
        return;
      }
    }

    try {
      // Release IO0 (BOOT pin) first so the chip boots to user code, not
      // download mode.  On ESP32-S3 USB-JTAG, DTR drives IO0: DTR=false →
      // IO0=high → normal boot.  Without this the chip re-enters DOWNLOAD
      // mode after the EN reset even though FLASH_END was sent with data=0.
      await serial.setDtr(false); // IO0 = HIGH → normal boot
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await serial.setRts(true); // EN = LOW → chip in reset
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await serial.setRts(false); // EN = HIGH → chip boots user code
      await Future<void>.delayed(const Duration(milliseconds: 50));
    } on SerialError catch (error, stackTrace) {
      if (needsOpen) await serial.close();
      throw _mapSerialError(error, stackTrace);
    }

    if (needsOpen) await serial.close();
    _d('[ESP] hardReset: done');
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
        // Yield to the event loop so that a stream of bad frames does not
        // spin-lock the UI isolate before the next serial read.
        await Future<void>.delayed(Duration.zero);
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
        _d('[ESP] read poll: available=$available readLength=$readLength '
            'remaining=${remaining.inMilliseconds}ms bufLen=${_readBuffer.length}');
        final chunk = await serial.read(readLength, timeout: remaining);
        if (chunk.isNotEmpty) {
          _d('[ESP] read got ${chunk.length} bytes: '
              '${chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          _readBuffer.add(chunk);
        }
      } on SerialError catch (error, stackTrace) {
        _d('[ESP] serial error type=${error.type} msg=${error.message}');
        if (error.type != SerialErrorType.timeout) {
          throw _mapSerialError(error, stackTrace);
        }
        // A serial timeout means no data arrived yet.  Yield once so that a
        // driver that returns timeout immediately does not spin-lock the isolate.
        await Future<void>.delayed(Duration.zero);
      }
    }

    final trailing = _readBuffer.toBytes();
    if (trailing.isNotEmpty) {
      // Check whether the trailing bytes are all printable ASCII (0x09 TAB,
      // 0x0A LF, 0x0D CR, or 0x20–0x7E printable).  If so, this is almost
      // certainly the ESP32 ROM banner text that the chip emits on every reset:
      //   "ESP-ROM:esp32s3-...\r\nBuild:...\r\nwaiting for download\r\n"
      // There is no 0xC0 SLIP byte in this banner, so the SLIP framer can
      // never complete a frame from it.  Clearing it and throwing a plain
      // timeout (not partialPacket) avoids the misleading error log that
      // flooded the console on every sync retry.
      final isAllAscii = trailing.every(
        (b) => b == 0x09 || b == 0x0A || b == 0x0D || (b >= 0x20 && b <= 0x7E),
      );
      if (isAllAscii) {
        _d('[ESP] ROM banner noise discarded (${trailing.length} ASCII bytes): '
            '"${String.fromCharCodes(trailing.where((b) => b >= 0x20 && b <= 0x7E))}"');
        _readBuffer.clear();
        throw const EspError(
          type: EspErrorType.timeout,
          message:
              'Timed out waiting for an ESP response (ROM banner discarded)',
        );
      }

      // Do NOT clear _readBuffer here.  Any bytes that accumulated (e.g. the
      // stub OHAI greeting that arrives immediately after MEM_END) must survive
      // the timeout so that a subsequent readRaw() call can retrieve them.
      // The next sendCommand / _tryExtractFrame call will see them again; if
      // they are not a valid ESP response they will be pushed back (see the
      // noise-frame handler in sendCommand), and readRaw() will drain them.
      _d('[ESP] partialPacket: ${trailing.length} bytes remain in buffer '
          '(preserved for readRaw): '
          '${trailing.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      throw const EspError(
        type: EspErrorType.partialPacket,
        message: 'A complete SLIP frame was not received before timeout',
      );
    }

    _d('[ESP] timeout: no bytes received');
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

    // -----------------------------------------------------------------------
    // SLIP framing note
    // -----------------------------------------------------------------------
    // In ESP's SLIP dialect the 0xC0 byte acts as BOTH a frame-end AND a
    // frame-start delimiter.  The END of one frame is the START of the next,
    // so a response may legitimately arrive WITHOUT a leading 0xC0 — the ROM
    // or stub simply omits the redundant open delimiter when the previous
    // frame's trailing 0xC0 already serves as the boundary.
    //
    // Strategy:
    //   1. Look for a leading cluster of 0xC0 bytes (normal "framed" case):
    //      advance `start` to the LAST of any consecutive 0xC0s so that we
    //      treat only the final one as the opening delimiter.
    //   2. If no leading 0xC0 exists but there IS a 0xC0 somewhere in the
    //      buffer, treat index 0 as the implicit start and the first 0xC0 as
    //      the closing delimiter (stub "frameless-start" case).
    // -----------------------------------------------------------------------

    var start = 0;
    final firstC0 = current.indexOf(0xC0);

    if (firstC0 < 0) {
      // No 0xC0 anywhere — not even a partial frame yet; wait for more data.
      return null;
    }

    if (current[0] == 0xC0) {
      // Normal case: buffer starts with (possibly multiple) 0xC0 delimiter(s).
      // Advance `start` to the LAST of the consecutive leading 0xC0 bytes.
      start = 0;
      while (start + 1 < current.length && current[start + 1] == 0xC0) {
        start++;
      }
    } else {
      // Frameless-start case: the stub omitted the opening 0xC0 (the previous
      // frame's trailing 0xC0 was already consumed).  Treat byte 0 as the
      // implicit start; the first 0xC0 in the buffer is the closing delimiter.
      //
      // Build a synthetic SLIP frame by prepending a 0xC0.
      final closingC0 = firstC0;
      final syntheticRaw = Uint8List(1 + closingC0 + 1);
      syntheticRaw[0] = 0xC0; // synthetic opening delimiter
      syntheticRaw.setRange(1, 1 + closingC0, current, 0);
      syntheticRaw[1 + closingC0] = 0xC0; // real closing delimiter
      final frame = SlipCodec.decode(syntheticRaw);
      final remaining = Uint8List.fromList(current.sublist(closingC0 + 1));
      _d('[ESP] _tryExtractFrame: frameless-start: closingC0=$closingC0'
          ' decodedLen=${frame?.length ?? -1}');
      _readBuffer.clear();
      if (remaining.isNotEmpty) {
        _readBuffer.add(remaining);
      }
      if (frame == null) {
        throw const EspError(
          type: EspErrorType.invalidResponse,
          message: 'Received an invalid SLIP frame (frameless-start)',
        );
      }
      if (frame.isEmpty) {
        return _tryExtractFrame();
      }
      return _FrameReadResult(rawFrame: syntheticRaw, packet: frame);
    }

    for (var index = start + 1; index < current.length; index++) {
      if (current[index] != 0xC0) {
        continue;
      }

      final rawFrame = Uint8List.fromList(current.sublist(start, index + 1));
      final frame = SlipCodec.decode(rawFrame);
      final remaining = Uint8List.fromList(current.sublist(index + 1));
      _d('[ESP] _tryExtractFrame: found frame [$start..$index]'
          ' rawLen=${rawFrame.length} decodedLen=${frame?.length ?? -1}');
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
      return _FrameReadResult(rawFrame: rawFrame, packet: frame);
    }

    // No closing 0xC0 found yet — buffer holds an incomplete frame.
    // Do NOT discard bytes; just return null so the caller reads more data.
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
      // The ROM bootloader sends opcode=0x00 for unsupported/unknown commands
      // (e.g. eraseFlash 0xD0 which is stub-only).  Rather than discarding the
      // error response as noise, remap opcode=0 to the caller's command opcode
      // so sendCommand can fail fast instead of waiting for the full timeout.
      if (opcodeValue == 0x00) {
        // The ROM bootloader sends opcode=0x00 for unsupported commands.
        // payload starts at byte 8; status=payload[0], error=payload[1].
        final statusByte = frame.length >= 10 ? frame[8] : 1;
        final errorByte = frame.length >= 11 ? frame[9] : 0;
        throw EspError(
          type: EspErrorType.invalidResponse,
          message:
              'ROM bootloader rejected command (status=$statusByte error=$errorByte)',
        );
      }
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
  const _FrameReadResult({required this.rawFrame, required this.packet});

  final Uint8List rawFrame;
  final Uint8List packet;
}

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

  /// Resets the target out of bootloader mode so it boots into user code.
  ///
  /// On ESP32-S3 this first clears the force-download-boot bit in
  /// RTC_CNTL_OPTION1_REG and then pulses the EN/RST line via RTS.
  Future<void> hardReset();

  /// Reads up to [count] raw bytes from the serial port within [timeout].
  ///
  /// Used after stub launch to consume the stub's `OHAI` greeting, which is
  /// emitted as plain bytes (not SLIP-encoded).  Any bytes already buffered
  /// from previous reads are included before issuing a new serial read.
  Future<List<int>> readRaw(int count, {Duration? timeout});

  /// Discards all buffered received data (both the in-memory read buffer and
  /// the hardware RX queue).  Called after the stub is loaded to purge any
  /// trailing bytes before resuming SLIP-framed communication.
  Future<void> flushRx();

  /// Writes [bytes] directly to the serial port without reading a response.
  ///
  /// Used to send the final MEM_END (execute=1) packet when uploading the
  /// flasher stub, so that the stub's `OHAI` greeting bytes are not consumed
  /// by the SLIP response scanner before [readRaw] can retrieve them.
  Future<void> writeRaw(List<int> bytes, {Duration? timeout});

  /// Closes the serial port, waits [waitBefore], then reopens it with the same
  /// configuration.  Used after the flasher stub starts to handle the USB CDC
  /// re-enumeration that occurs when the stub re-initialises the USB peripheral.
  ///
  /// The port is reopened with up to 10 retries spaced 200 ms apart.
  Future<void> reopenPort({Duration waitBefore});
}

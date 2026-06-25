# ⚡ flutter_esptool

[![pub.dev version](https://img.shields.io/pub/v/flutter_esptool.svg)](https://pub.dev/packages/flutter_esptool)
[![pub points](https://img.shields.io/pub/points/flutter_esptool)](https://pub.dev/packages/flutter_esptool/score)
[![CI](https://github.com/pvagnozzi/flutter_esptool/actions/workflows/ci.yml/badge.svg)](https://github.com/pvagnozzi/flutter_esptool/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A professional Flutter/Dart toolkit for **ESP8266 / ESP32** serial bootloader
operations: chip detection, flash write/erase/read, MAC address queries, and
protocol-safe transport abstractions — all in pure Dart.

---

## Overview

`flutter_esptool` implements the Espressif ROM/stub serial bootloader protocol
in pure Dart.  It provides:

- **Typed results** – every operation returns `Result<T>` (`Success` /
  `Failure`) so errors are handled at compile time.
- **Layered architecture** – `application`, `domain`, `transport`,
  `infrastructure`, and `models` layers keep concerns separated.
- **Hardware-free testing** – services accept abstract `EspTransportInterface`
  instances so they can be exercised with mock transports in unit and
  integration tests.
- **Resilience** – optional retry policy (exponential back-off) and circuit
  breaker protect against cascading connection failures.

---

## Features

- 🔍 **Chip detection** – identifies ESP8266, ESP32, ESP32-S2, ESP32-S3, and
  ESP32-C3 via ROM magic register reads.
- 💾 **Flash write** – chunked `FLASH_BEGIN` / `FLASH_DATA` / `FLASH_END`
  flow with optional zlib (`FLASH_DEFL_*`) compression.
- 📖 **Flash read** – reads flash using `READ_FLASH_SLOW` or direct SPI
  register manipulation (no stub required).
- 🗑️ **Flash erase** – full-chip (`ERASE_FLASH`) or region (`ERASE_REGION`)
  erase with auto-sized timeout.
- ✅ **MD5 verification** – post-write integrity check via on-device
  `FLASH_MD5` command.
- 🌐 **MAC address** – reads Espressif-fused MAC from EFUSE registers.
- ℹ️ **Flash info** – queries JEDEC manufacturer/device/capacity identifiers
  via direct SPI register access.
- 📦 **SLIP codec** – encodes and decodes Serial Line IP framing used by the
  ROM bootloader.
- 🗂️ **Partition table** – parses binary ESP partition tables.
- 🖼️ **Image parser** – validates and parses ESP boot image headers and
  segments.
- 🔄 **Resilience** – `EspRetryPolicy` (exponential back-off) +
  `EspCircuitBreaker` (open/half-open/closed state machine).
- 🔌 **Transport adapter** – `EspTransport` (concrete) and
  `EspResilientTransport` (decorator) built on `platform_serial`.

---

## Installation

```bash
flutter pub add flutter_esptool
```

Or add the dependency manually to `pubspec.yaml`:

```yaml
dependencies:
  flutter_esptool: ^0.1.3
```

Then fetch:

```bash
flutter pub get
```

---

## Quick Start

```dart
import 'dart:typed_data';
import 'package:flutter_esptool/flutter_esptool.dart';

Future<void> flashFirmware(String portName, Uint8List firmware) async {
  // 1. Build configuration.
  final config = EspConfig(portName: portName);

  // 2. Create the transport (optionally wrap with EspResilientTransport).
  final transport  = EspTransport();
  final connection = ConnectionService(transport);
  final detection  = ChipDetectionService(transport);
  final flash      = FlashService(transport: transport);

  // 3. Connect and synchronise with the ROM bootloader.
  final connectResult = await connection.connect(config);
  if (connectResult.isFailure) {
    connectResult.fold((_) {}, (err) => print('Connect error: ${err.message}'));
    return;
  }

  // 4. Detect the chip.
  final chipResult = await detection.detect();
  chipResult.fold(
    (chip) => print('Chip: ${chip.description}  MAC: ${chip.macAddress}'),
    (err)  => print('Detection error: ${err.message}'),
  );

  // 5. Write firmware to flash address 0x0000.
  final writeResult = await flash.writeFlash(
    FlashParameters(
      offset: 0x0000,
      data: firmware,
      compress: true,
      verify: true,
    ),
  );

  writeResult.fold(
    (_)   => print('Flash write complete ✅'),
    (err) => print('Flash write failed: ${err.message}'),
  );

  // 6. Disconnect.
  await connection.disconnect();
}
```

---

## Platform Support

| Platform | Supported |
|----------|:---------:|
| Linux    |     ✅     |
| macOS    |     ✅     |
| Windows  |     ✅     |
| Android  |     ❌     |
| iOS      |     ❌     |

> **Note:** Serial port access requires a physical UART / USB-serial adapter.
> Mobile platforms (Android, iOS) do not expose the required serial APIs.

---

## API Reference

Full API documentation is published on pub.dev:

👉 <https://pub.dev/documentation/flutter_esptool/latest/>

### Key classes

| Class | Description |
|-------|-------------|
| `EspConfig` | Serial session configuration (port name, baud rate, timeout) |
| `EspTransport` | SLIP-based serial transport over `platform_serial` |
| `EspResilientTransport` | Transport decorator with retry and circuit breaker |
| `ConnectionService` | Opens the port and synchronises with the ROM bootloader |
| `ChipDetectionService` | Reads chip family and MAC address from ROM registers |
| `FlashService` | Write, read, erase, and verify flash |
| `InfoService` | Queries chip info and flash JEDEC identifier |
| `EspCircuitBreaker` | Protects against cascading connection failures |
| `EspRetryPolicy` | Configures exponential back-off retry behaviour |
| `SlipCodec` | Encodes and decodes SLIP frames |
| `PartitionTable` | Parses binary ESP partition tables |
| `EspImageParser` | Validates and parses ESP boot image headers |
| `Result<T>` | Typed success/failure result used by every operation |

---

## Contributing

Contributions are welcome!  Please read [CONTRIBUTING.md](CONTRIBUTING.md) for
guidelines on the fork → branch → PR workflow, code style, test requirements,
and commit message format.

---

## License

This project is licensed under the [MIT License](LICENSE).

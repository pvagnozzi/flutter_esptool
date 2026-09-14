# ⚡ flutter_esptool

[![pub.dev version](https://img.shields.io/pub/v/flutter_esptool.svg)](https://pub.dev/packages/flutter_esptool)
[![pub points](https://img.shields.io/pub/points/flutter_esptool)](https://pub.dev/packages/flutter_esptool/score)
[![Dart SDK version](https://img.shields.io/badge/dart-3.4+-blue.svg)](https://dart.dev/get-dart)
[![Flutter version](https://img.shields.io/badge/flutter-3.16+-blue.svg)](https://flutter.dev/get-started)
[![CI](https://github.com/pvagnozzi/flutter_esptool/actions/workflows/ci.yml/badge.svg)](https://github.com/pvagnozzi/flutter_esptool/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A **professional-grade** Flutter/Dart toolkit for **ESP8266 / ESP32** serial bootloader operations: chip detection, flash write/erase/read, MAC address queries, and protocol-safe transport abstractions — all in **pure Dart**.

---

## Overview

`flutter_esptool` implements the **Espressif ROM/stub serial bootloader protocol** in pure Dart.  It provides:

- **Type-Safe Results** – Every operation returns `Result<T>` (`Success` / `Failure`) so errors are handled at compile time with exhaustive pattern matching.
- **Layered Architecture** – `application`, `domain`, `transport`, `infrastructure`, and `models` layers keep concerns separated and testable.
- **Hardware-Free Testing** – Services accept abstract `EspTransportInterface` instances so they can be exercised with mock transports in unit and integration tests.
- **Production Resilience** – Optional retry policy (exponential back-off) and circuit breaker protect against cascading connection failures in real deployments.
- **Standards Compliance** – Adheres to Flutter best practices, Dart effective patterns, and pub.dev scoring requirements.

---

## Features

- 🔍 **Chip Detection** – Identifies ESP8266, ESP32, ESP32-S2, ESP32-S3, and ESP32-C3 via ROM magic register reads.
- 💾 **Flash Write** – Chunked `FLASH_BEGIN` / `FLASH_DATA` / `FLASH_END` flow with optional zlib (`FLASH_DEFL_*`) compression.
- 📖 **Flash Read** – Reads flash using `READ_FLASH_SLOW` or direct SPI register manipulation (no stub required).
- 🗑️ **Flash Erase** – Full-chip (`ERASE_FLASH`) or region (`ERASE_REGION`) erase with auto-sized timeout.
- ✅ **MD5 Verification** – Post-write integrity check via on-device `FLASH_MD5` command.
- 🌐 **MAC Address** – Reads Espressif-fused MAC from EFUSE registers.
- ℹ️ **Flash Info** – Queries JEDEC manufacturer/device/capacity identifiers via direct SPI register access.
- 📦 **SLIP Codec** – Encodes and decodes Serial Line IP framing used by the ROM bootloader.
- 🗂️ **Partition Table** – Parses binary ESP partition tables with validation.
- 🖼️ **Image Parser** – Validates and parses ESP boot image headers and segments.
- 🔄 **Resilience** – `EspRetryPolicy` (exponential back-off) + `EspCircuitBreaker` (open/half-open/closed state machine).
- 🔌 **Transport Adapter** – `EspTransport` (concrete) and `EspResilientTransport` (decorator) built on `platform_serial`.

---

## Installation

### Stable Release

```bash
flutter pub add flutter_esptool
```

### Manual Setup

Add to `pubspec.yaml`:

```yaml
dependencies:
  flutter_esptool: ^0.2.0
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
  // 1. Build configuration with serial port settings.
  final config = EspConfig(
    portName: portName,
    initialBaudRate: 115200,
    flashBaudRate: 460800,
  );

  // 2. Create transport with optional resilience wrapper.
  final transport = EspTransport();
  final resilientTransport = EspResilientTransport(
    inner: transport,
    retryPolicy: const EspRetryPolicy(maxAttempts: 3),
  );

  // 3. Create application services.
  final connection = ConnectionService(resilientTransport);
  final detection = ChipDetectionService(resilientTransport);
  final flash = FlashService(transport: resilientTransport);

  try {
    // 4. Connect and synchronise with ROM bootloader.
    final connectResult = await connection.connect(config);
    if (connectResult.isFailure) {
      connectResult.fold(
        (_) {},
        (err) => print('❌ Connect error: ${err.message}'),
      );
      return;
    }

    // 5. Detect the chip.
    final chipResult = await detection.detect();
    chipResult.fold(
      (chip) => print('✅ Chip: ${chip.description}  MAC: ${chip.macAddress}'),
      (err) => print('❌ Detection error: ${err.message}'),
    );

    // 6. Write firmware to flash address 0x0000.
    final writeResult = await flash.writeFlash(
      FlashParameters(
        offset: 0x0000,
        data: firmware,
        compress: true,
        verify: true,
      ),
    );

    writeResult.fold(
      (_) => print('✅ Flash write complete!'),
      (err) => print('❌ Flash write failed: ${err.message}'),
    );
  } finally {
    // 7. Always disconnect cleanly.
    await connection.disconnect();
  }
}
```

---

## Platform Support

| Platform | Desktop | Mobile |
|----------|:-------:|:------:|
| **Linux** |    ✅    |   ❌   |
| **macOS** |    ✅    |   ❌   |
| **Windows** |    ✅    |   ❌   |
| **Android** |    ❌    |   ❌   |
| **iOS**   |    ❌    |   ❌   |

> **Note:** Serial port access requires a physical UART / USB-serial adapter. Mobile platforms (Android, iOS) do not expose the required serial APIs.

---

## API Reference

Full API documentation is published on pub.dev:

👉 **[flutter_esptool API Docs](https://pub.dev/documentation/flutter_esptool/latest/)**

### Key Classes

| Class | Description |
|-------|-------------|
| `EspConfig` | Serial session configuration (port name, baud rate, timeout, reset mode) |
| `EspTransport` | SLIP-based serial transport over `platform_serial` |
| `EspResilientTransport` | Transport decorator with retry policy and circuit breaker |
| `ConnectionService` | Opens the port, resets device, and synchronises with ROM bootloader |
| `ChipDetectionService` | Reads chip family and MAC address from ROM registers |
| `FlashService` | Write, read, erase, and verify flash memory |
| `InfoService` | Queries chip info and flash JEDEC identifier |
| `EfuseService` | eFuse programming for ESP32-S3 Secure Boot V2 |
| `EspCircuitBreaker` | Protects against cascading connection failures |
| `EspRetryPolicy` | Configures exponential back-off retry behaviour |
| `SlipCodec` | Encodes and decodes SLIP frames |
| `PartitionTable` | Parses binary ESP partition tables |
| `EspImageParser` | Validates and parses ESP boot image headers |
| `Result<T>` | Type-safe success/failure result used by every operation |

---

## Architecture

The package follows a clean, layered architecture:

```
┌──────────────────────────────────────────────────┐
│         Application Services                     │
│ ConnectionService, ChipDetectionService,         │
│ FlashService, InfoService, EfuseService          │
└──────────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────────┐
│       Domain Interfaces & Models                 │
│ ChipDetectorInterface, FlashServiceInterface     │
│ StubLoaderInterface, ChipFamily                  │
└──────────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────────┐
│      Transport & Resilience Layers               │
│ EspTransport, EspResilientTransport,             │
│ EspRetryPolicy, EspCircuitBreaker                │
└──────────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────────┐
│    Infrastructure & Protocol Codecs              │
│ SlipCodec, EspImageParser, PartitionTable,       │
│ ReedSolomon12, ZlibHelper                        │
└──────────────────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────────┐
│        Models & Error Handling                   │
│ Result<T>, EspError, EspCommand,                 │
│ EspConfig, EspChipInfo, EspProgress              │
└──────────────────────────────────────────────────┘
```

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:

- Fork → branch → PR workflow
- Code style and analysis requirements
- Test requirements (unit, integration, e2e)
- Commit message format (Conventional Commits)
- Documentation standards

---

## Testing

Run all test tiers:

```bash
# Unit tests (no hardware)
flutter test test/unit

# Integration tests (mock transport)
flutter test test/integration

# End-to-end tests (mock device)
flutter test test/e2e

# Full suite with coverage
flutter test --coverage
```

---

## Examples

See the `example/` directory for complete applications:

- **`esptool_cli`** – Professional command-line tool for ESP chip programming
- **`esptool_ui`** – Feature-rich Flutter UI application with real-time monitoring

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history and version notes.

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Acknowledgments

- Based on the [Espressif esptool.py](https://github.com/espressif/esptool) reference implementation
- Inspired by the official ESP8266 and ESP32 bootloader documentation
- Built with the [Flutter](https://flutter.dev) and [Dart](https://dart.dev) ecosystems

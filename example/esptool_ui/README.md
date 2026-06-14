# esptool_ui

Flutter example app for `flutter_esptool`.

## Features

- Serial port discovery through `platform_serial`
- Live ESP bootloader connection workflow
- Chip detection, MAC read, flash info, erase, write, and MD5 actions
- Multilingual UI with flag assets
- Light and dark theme support

## Run the demo app

```bash
flutter pub get
flutter run
```

## Hardware integration test

The hardware integration test is disabled by default. To run it, you must pass the serial port explicitly.

```bash
flutter test integration_test/esp32_hardware_test.dart --dart-define=RUN_ESP_HARDWARE_TESTS=true --dart-define=ESP_PORT=COM22
```

This test path is non-destructive by default and performs connect/detect/read-only checks only.

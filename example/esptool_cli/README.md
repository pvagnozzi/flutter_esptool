# esptool_cli

Command-line example for `flutter_esptool`.

## Usage

Run commands from this directory:

```bash
flutter pub get
dart run bin/esptool.dart version
```

All real-hardware commands require an explicit serial port. There is **no default port fallback**.

Safe read-only examples:

```bash
dart run bin/esptool.dart chip_id --port COM22
dart run bin/esptool.dart read_mac --port COM22
dart run bin/esptool.dart flash_id --port COM22
```

Other commands also require `--port`, for example:

```bash
dart run bin/esptool.dart read_flash --port COM22 --address 0x0 --length 0x100 --filename dump.bin
dart run bin/esptool.dart write_flash --port COM22 --address 0x1000 --filename firmware.bin
dart run bin/esptool.dart erase_flash --port COM22
dart run bin/esptool.dart erase_region --port COM22 --address 0x1000 --length 0x1000
```

## Hardware integration tests

The hardware integration suite is disabled by default and must be enabled explicitly with a serial port.

Safe/read-only verification path:

```bash
flutter test integration_test/hardware_e2e_test.dart --dart-define=RUN_ESP_HARDWARE_TESTS=true --dart-define=ESP_PORT=COM22
```

Destructive flash tests remain gated by a second flag:

```bash
flutter test integration_test/hardware_e2e_test.dart --dart-define=RUN_ESP_HARDWARE_TESTS=true --dart-define=ESP_PORT=COM22 --dart-define=RUN_ESP_DESTRUCTIVE_HARDWARE_TESTS=true
```

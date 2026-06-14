# Demo Application

The package includes a professional demonstration app:

- Path: `example/esptool_ui`
- Theme modes: light and dark
- Splash screen: built-in startup gate
- Languages: `en`, `fr`, `es`, `pt`, `de`, `it`, `nl`, `ru`, `ar`, `he`, `zh`, `ja`, `ko`
- Features: connect, chip detect, MAC read, flash info, flash write, erase, MD5

Run:

```bash
cd example\esptool_ui
flutter pub get
flutter run
```

Hardware integration test (explicit port required):

```bash
flutter test integration_test/esp32_hardware_test.dart --dart-define=RUN_ESP_HARDWARE_TESTS=true --dart-define=ESP_PORT=COM22
```

The demo uses the package's real `EspTransport` with `platform_serial`. If no serial plugin or ports are available, the UI stays usable and surfaces that state clearly.

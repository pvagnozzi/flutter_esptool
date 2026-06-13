---
description: Flutter/Dart package implementation conventions for flutter_esptool
applyTo: "lib/**/*.dart,test/**/*.dart,example/**/*.dart"
---

# Flutter package conventions

- Keep APIs `Result<T>`-based in service layers; do not switch to exception-only flow.
- Maintain typed `EspErrorType` mapping when adding new failure paths.
- Keep protocol serialization little-endian and verify packet structure in tests.
- Prefer transport abstraction (`EspTransportInterface`) in services and tests.
- For tests, use scripted or mocked transport implementations, not physical serial devices.

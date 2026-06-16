# Copilot Instructions for `flutter_esptool`

## Build, test, and lint

Run commands from the repository root (`flutter_esptool`):

```bash
flutter pub get
flutter analyze
flutter test
```

Run one test scope at a time:

```bash
flutter test test\unit\transport\slip_codec_test.dart
flutter test test\integration\transport_mock_test.dart
flutter test test\e2e\flash_flow_e2e_test.dart
```

Run a single test by name:

```bash
flutter test test\unit\transport\slip_codec_test.dart --plain-name "round-trips a payload through encode and decode"
```

Run focused subsets while iterating on protocol work:

```bash
flutter test test\unit\transport
flutter test test\unit\infrastructure
```

## High-level architecture

- Public API is the barrel file `lib/flutter_esptool.dart`, which re-exports services, domain interfaces, transport, infrastructure parsers/builders, and models.
- The code is layered under `lib/src/`:
  - `application/`: orchestration services (`ConnectionService`, `ChipDetectionService`, `FlashService`, `InfoService`, `StubLoaderService`)
  - `domain/`: stable interfaces and core domain types
  - `transport/`: ESP wire protocol and serial transport (`EspTransport`, `SlipCodec`)
  - `infrastructure/`: binary/image/partition/compression helpers
  - `models/`: protocol/config/error/result/progress DTOs
- Typical runtime call path is:
  - `ConnectionService.connect(EspConfig)` -> transport open/reset/sync retries
  - `ChipDetectionService.detect()` -> `readReg` on chip magic + MAC registers
  - `FlashService.writeFlash(FlashParameters)` -> begin/data/end (+ optional MD5)
- `EspTransport` is the protocol boundary:
  - builds command packets (`0x00`, opcode, little-endian fields, payload),
  - wraps them in SLIP frames,
  - reads/accumulates serial chunks until a complete frame exists,
  - parses response packets into `EspResponse`.
- Application services depend on `EspTransportInterface`, not concrete serial classes, so tests can inject mock/scripted transports (`test/integration/transport_mock_test.dart`, `test/e2e/flash_flow_e2e_test.dart`).
- Flash writing flow in `FlashService` is: split image blocks (`FlashImageBuilder`) -> optional deflate (`ZlibHelper`) -> begin/data/end command sequence -> optional MD5 verification (`flashMd5` + local MD5).
- `StubLoaderService` is intentionally a placeholder in this version (`stubNotAvailable`), so raw flash-read flows that require stub support are expected to fail with typed errors.

## Key codebase conventions

- **Result-driven API:** service/parser APIs return `Result<T>` (`Success`/`Failure`) instead of throwing for expected operation outcomes.
- **Error typing:** failures use `EspError` with a specific `EspErrorType`; map errors to the closest protocol/transport category.
- **Transport exception boundary:** `EspTransport` may throw `EspError`; higher-level services catch and convert to `Failure(...)`.
- **Protocol encoding:** use `ByteData` with `Endian.little` for all wire fields, register payloads, flash headers, and partition parsing.
- **Imports and style:** use package imports (`always_use_package_imports`) and single quotes (`prefer_single_quotes`) per `analysis_options.yaml`.
- **Strict analysis settings:** keep `strict-casts`, `strict-inference`, and `strict-raw-types` compatibility.
- **Hardware-free tests:** tests should use mocks/fakes (`mocktail`, scripted transport/serial implementations), not real serial hardware.
- **Protocol tests should assert bytes, not only booleans:** in transport tests, validate encoded packet contents and decoded response fields (see `test/integration/transport_mock_test.dart`).
- **Use deterministic scripted command queues for flow tests:** e2e-style tests in this repo model command/response order by opcode queues (`ScriptedTransport`) to verify multi-step flashing logic.
- **Partial frame behavior is first-class:** when changing transport/SLIP logic, keep coverage for split reads and frame accumulation semantics (`sendCommand accumulates partial packets`, `partial packet accumulation works across split reads`).

## Security and vulnerability management

- Treat every dependency change as a security event: review changelogs and CVE advisories before merging.
- Prefer fixed or bounded versions for security-sensitive tooling used in CI and release workflows.
- For vulnerability triage, classify findings as:
  - `critical/high`: block release and require remediation.
  - `medium`: remediate before the next tagged release.
  - `low`: document and track with owner + due date.
- When touching transport, parser, compression, or file handling code:
  - validate bounds and malformed payload behavior;
  - add/adjust tests for bad-path and edge-path inputs;
  - map failures to typed `EspErrorType` instead of silent fallback behavior.

## Test automation expectations (including UI)

- Any logic change should include or update:
  - unit tests for pure logic and branch behavior;
  - integration tests for service + transport interaction;
  - e2e/scripted-flow tests for multi-step protocol workflows.
- For `example/esptool_ui`, include widget tests for:
  - good path (expected success UX),
  - bad path (typed errors surfaced clearly),
  - edge cases (empty input, retry states, long-running operations).
- Keep tests deterministic: avoid wall-clock dependency and non-deterministic ordering.
- Prefer reusable test fixtures/builders over duplicated inline setup.

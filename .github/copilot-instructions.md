# Copilot Instructions for `flutter_esptool`

## Project Context

`flutter_esptool` is a Flutter/Dart package that implements the ESP32/ESP8266
serial bootloader protocol. It enables chip detection, flash writing, and
firmware operations over serial without requiring Python or esptool.py.

**Architecture layers** (under `lib/src/`):

| Layer | Path | Responsibility |
|---|---|---|
| Domain | `domain/` | Interfaces, core types, error types |
| Application | `application/` | Orchestration services |
| Infrastructure | `infrastructure/` | Binary, image, partition, compression |
| Transport | `transport/` | ESP wire protocol + SLIP framing |

**Key patterns**:

- `EspResult<T>` (`Success<T>` / `Failure`) — every fallible operation
  returns a typed result, never throws.
- `EspResilientTransport` — wraps `EspTransport` with retry logic and
  circuit-breaker semantics for unstable serial connections.
- `EspTransportInterface` — dependency-injection boundary used in tests to
  inject scripted/mocked transports (no physical hardware required).
- `EspErrorType` — typed error enum; all failures map to a specific category
  (e.g. `connectionFailed`, `flashWriteError`, `stubNotAvailable`).

**Public API entry point**: `lib/flutter_esptool.dart` (barrel file).

---

## Code Review Guidelines

When reviewing a PR, Copilot must check all of the following:

### 1. Null Safety

- No `late` fields without guaranteed initialisation before first access.
- No `!` (bang operator) on nullable values unless provably non-null at that
  site; prefer `?.` / null-aware operators or early `return Failure(...)`.

### 2. Async / Await

- Every `Future<T>` call site must be `await`-ed or explicitly handled.
- No fire-and-forget `unawaited()` unless wrapped in error-logging callback.
- Avoid `async` functions that never use `await` (use `Future.value` instead).

### 3. EspResult Pattern

- Every method that can fail **must** return `EspResult<T>` (alias for
  `Result<T>` from the domain layer).
- Do not throw across service/application layer boundaries; catch at the
  transport boundary and convert with `Failure(EspError(...))`.
- `switch`/`when` on result type must be exhaustive — no silent fallbacks.

### 4. Resource Cleanup

- Serial port (or any `Closeable`) **must** be closed in a `finally` block.
- Every `StreamSubscription` created in a service must be cancelled in
  `dispose()` or an equivalent teardown method.
- `StreamController` instances must be closed when no longer needed.

### 5. Test Coverage

- Every **public** method added or modified must have at least one unit test.
- New failure paths must have a corresponding bad-path test.
- Edge cases (empty payload, max-size payload, partial frames) must be covered
  if the change touches transport or parser code.

### 6. Dartdoc

- Every public class, method, property, and typedef must have `///` comments.
- Include `@param`, `@returns`, and `@throws` (or note "never throws") for
  complex signatures.
- Avoid redundant re-stating of the function name; describe *why*, not *what*.

### 7. Error Types

- Use `EspErrorType` values instead of `Exception` or `Error` subclasses.
- Do not wrap `EspError` inside another `EspError`; flatten the chain.
- String messages in `EspError` should be human-readable for end-user display.

### 8. Platform Compatibility

- Verify that added code compiles and behaves correctly on Linux, macOS, and
  Windows (path separators, line endings, serial device naming).
- Avoid `dart:io` `Platform.isXxx` branches in library code; prefer the
  `platform` abstraction from the domain layer.
- No hard-coded Unix paths (e.g. `/dev/ttyUSB0`) in non-example library code.

---

## Commit Message Convention

Use **Conventional Commits** (`https://www.conventionalcommits.org`):

```
<type>(<scope>): <short summary>

[optional body]

[optional footers]
```

**Types**: `feat` | `fix` | `docs` | `style` | `refactor` | `test` |
`chore` | `ci`

**Scopes** (optional): `transport` | `flash` | `chip` | `stub` | `models` |
`infra` | `ci` | `deps` | `example`

Examples:

```
feat(transport): add EspResilientTransport circuit-breaker
fix(flash): correct MD5 verification byte order
test(transport): add partial-frame accumulation coverage
chore(deps): bump mocktail to 1.0.4
ci: split e2e job from integration job
```

Breaking changes must include a `BREAKING CHANGE:` footer or a `!` suffix:

```
feat(models)!: rename EspStatus to EspConnectionStatus
```

---

## Test Structure

```
test/
  unit/           # Pure logic, no I/O — fast, fully mocked
    transport/    # SLIP codec, packet encoding/decoding
    models/       # DTO serialisation/parsing
    resilience/   # Circuit-breaker, retry policy
    infrastructure/ # Image builder, zlib, partition parser
  integration/    # Multiple components wired together
    transport_mock_test.dart   # Full protocol flow via ScriptedTransport
    info_service_protocol_test.dart
  e2e/            # Multi-step scripted flows (no real hardware required)
    flash_flow_e2e_test.dart   # begin/data/end/MD5 command sequence
```

**Rules**:

- `test/unit/` — inject mocks via `mocktail`; no serial port, no I/O.
- `test/integration/` — use `ScriptedTransport` (opcode queue) to validate
  service-to-transport interaction.
- `test/e2e/` — use `ScriptedTransport` for deterministic multi-step flows;
  mark hardware-dependent tests with `@Skip('requires hardware')`.
- No wall-clock dependency (`Future.delayed`); use fake async where needed.
- Prefer reusable builders/fixtures over duplicated inline setup.

**Commands**:

```bash
flutter pub get
flutter analyze
flutter test
flutter test test/unit
flutter test test/integration
flutter test test/e2e
flutter test test/unit/transport/slip_codec_test.dart
```

---

## PR Review Checklist

Copilot must verify all 10 items on every PR:

1. **[ ] Null safety** — no unsafe `!` or uninitialised `late`.
2. **[ ] Async hygiene** — every `Future` is `await`-ed or handled.
3. **[ ] EspResult usage** — fallible methods return `EspResult<T>`.
4. **[ ] Resource cleanup** — ports and subscriptions released properly.
5. **[ ] Test coverage** — new public methods have at least one test.
6. **[ ] Dartdoc** — public APIs have `///` documentation.
7. **[ ] Error types** — `EspErrorType` used, no raw `Exception`.
8. **[ ] Platform compat** — no platform-specific paths or assumptions.
9. **[ ] CHANGELOG** — entry added if change is user-visible.
10. **[ ] Breaking change** — `BREAKING CHANGE` noted in commit and PR.

---

## Code Style

| Rule | Value |
|---|---|
| Formatter | `dart format --line-length 80` |
| Quote style | `prefer_single_quotes` |
| Import style | `always_use_package_imports` |
| Null safety | strict (`strict-casts`, `strict-inference`, `strict-raw-types`) |
| Linter | `package:flutter_lints` + project `analysis_options.yaml` |

**Protocol encoding**: always use `ByteData` with `Endian.little` for wire
fields, register payloads, flash headers, and partition entries.

**File organisation**: one public class or mixin per file; private helpers may
share the file with their primary class.

---

## Security and Vulnerability Management

- Every dependency change is a security event: review changelogs and CVE
  advisories before merging.
- Classify findings: `critical/high` block release; `medium` fix before next
  tag; `low` document with owner + due date.
- When touching transport, parser, compression, or file handling code:
  - validate bounds and malformed-payload behaviour;
  - add/adjust tests for bad-path and edge-path inputs;
  - map failures to typed `EspErrorType` (no silent fallbacks).
- Use trusted publishing (OIDC) for pub.dev; avoid long-lived secrets.

---

## PR / Release Automation

- PR checks run: `analyze` → `unit` → `integration` → `e2e` (separate jobs).
- Auto-merge is allowed only after all jobs succeed and only for owner PRs to
  `main`.
- Never bypass failing tests to publish.
- Publish workflow is downstream from the `main` merge and uses OIDC.

# Project Operations and Quality Guide

This guide provides a complete operational view of `flutter_esptool`, with architecture, delivery workflows, security practices, and full-spectrum testing guidance for package and UI layers.

## 1. Project profile

`flutter_esptool` is a layered Flutter/Dart package for ESP8266/ESP32 serial bootloader workflows. It is designed around:

- strict protocol correctness;
- typed failure handling with `Result<T>`;
- deterministic hardware-free testing;
- operational quality gates for CI and releases.

### 1.1 Capability map

```mermaid
mindmap
  root((flutter_esptool))
    Connection
      Serial open/close
      Bootloader sync/retry
    Device discovery
      Chip magic detect
      MAC address read
    Flash operations
      Begin/Data/End flows
      Optional compression
      Optional MD5 verify
    Quality
      Unit/Integration/E2E tests
      UI widget tests
      Security and vulnerability gates
```

## 2. Architecture and runtime flow

### 2.1 Layered architecture

```mermaid
flowchart TB
  API[Public API<br/>lib/flutter_esptool.dart]
  APP[Application services]
  DOMAIN[Domain contracts]
  TRANSPORT[Transport: packet + SLIP + serial]
  INFRA[Infrastructure: image, partition, compression]
  MODELS[Models: config, result, error, DTOs]
  SERIAL[platform_serial]
  DEVICE[ESP ROM bootloader]

  API --> APP
  API --> DOMAIN
  API --> MODELS
  APP --> DOMAIN
  APP --> TRANSPORT
  APP --> INFRA
  APP --> MODELS
  TRANSPORT --> MODELS
  TRANSPORT --> SERIAL
  SERIAL --> DEVICE
```

### 2.2 End-to-end operation workflow

```mermaid
sequenceDiagram
  participant Client as UI/CLI/Test
  participant Conn as ConnectionService
  participant Detect as ChipDetectionService
  participant Flash as FlashService
  participant Tx as EspTransport
  participant ESP as ESP ROM

  Client->>Conn: connect(config)
  Conn->>Tx: open + reset + sync retries
  Tx->>ESP: SYNC (SLIP frame)
  ESP-->>Tx: SYNC response
  Conn-->>Client: Success/Failure

  Client->>Detect: detect()
  Detect->>Tx: READ_REG (magic + MAC words)
  Tx->>ESP: register reads
  ESP-->>Tx: register values
  Detect-->>Client: chip info

  Client->>Flash: writeFlash(params)
  Flash->>Tx: FLASH_BEGIN / FLASH_DATA / FLASH_END
  Tx->>ESP: command sequence
  ESP-->>Tx: command responses
  Flash-->>Client: Success/Failure
```

## 3. Security and vulnerability management

Security work in this project is operational, test-driven, and release-gated.

### 3.1 Vulnerability lifecycle

```mermaid
flowchart LR
  Detect[Detect: dependency scan/code review/advisory] --> Triage[Triage severity + exploitability]
  Triage --> Repro[Reproduce with focused test]
  Repro --> Patch[Apply smallest safe patch]
  Patch --> Verify[Run targeted unit/integration/e2e/ui tests]
  Verify --> Gate{Any high/critical unresolved?}
  Gate -- yes --> Hold[Hold release + track owner]
  Gate -- no --> Release[Allow release]
```

### 3.2 Severity policy

| Severity | Release policy | Required action |
| --- | --- | --- |
| Critical / High | Block release | Immediate fix and regression tests |
| Medium | Must be planned before next release | Patch + test coverage + issue tracking |
| Low | Track and monitor | Document risk and due date |

### 3.3 Secure coding guardrails

1. Preserve typed failures (`EspError`, `EspErrorType`) and avoid silent fallbacks.
2. Validate malformed or boundary payloads in transport/parser changes.
3. Keep protocol serialization little-endian and test byte-level correctness.
4. Keep automation deterministic and free of hardware dependency by default.

## 4. Full-spectrum test strategy

### 4.1 Test taxonomy

| Test type | Target | Primary intent |
| --- | --- | --- |
| Unit | codec/parser/model/helpers | branch, boundary, and transformation correctness |
| Integration | services + transport abstraction | orchestration and command-level behavior |
| E2E/scripted | full operation flows | multi-step protocol correctness without hardware |
| UI/widget | `example/esptool_ui` | state transitions, user feedback, and error UX |

### 4.2 Coverage model by scenario class

```mermaid
flowchart TD
  Changed[Changed file/workflow] --> Good[Good path tests]
  Changed --> Bad[Bad path tests]
  Changed --> Edge[Edge/boundary tests]
  Good --> Matrix[Test matrix updated]
  Bad --> Matrix
  Edge --> Matrix
  Matrix --> Execute[Run targeted scopes]
  Execute --> Gate{All scenarios covered?}
  Gate -- no --> Add[Generate missing tests]
  Gate -- yes --> Done[Ready for review]
```

### 4.3 UI test guidance

For `example/esptool_ui`:

1. Verify loading, success, and failure states for each user operation.
2. Assert visible feedback content (messages, button state, progress indicators).
3. Include edge behavior (empty input, retry transitions, cancellation).
4. Use deterministic fake services/transports to avoid flaky tests.

## 5. CI/CD operational workflow

```mermaid
flowchart LR
  Dev[Developer change] --> Analyze[flutter analyze]
  Analyze --> Unit[Unit tests]
  Unit --> Integration[Integration tests]
  Integration --> E2E[E2E/scripted tests]
  E2E --> UI[UI tests]
  UI --> Security[Dependency + vulnerability checks]
  Security --> PublishGate{Release criteria met?}
  PublishGate -- yes --> Tag[Tag + publish readiness]
  PublishGate -- no --> Remediate[Fix and re-run]
```

## 6. Operational runbook

### 6.1 Standard local workflow

```bash
flutter pub get
flutter analyze
flutter test
```

### 6.2 Focused execution during feature work

```bash
flutter test test\unit\transport
flutter test test\unit\infrastructure
flutter test test\integration\transport_mock_test.dart
flutter test test\e2e\flash_flow_e2e_test.dart
```

### 6.3 UI-focused validation

```bash
cd example\esptool_ui
flutter test
```

## 7. Quality gates and release readiness

Release readiness requires:

1. Analyzer and required tests passing for changed scopes.
2. Security triage completed with no unresolved high/critical vulnerabilities.
3. Regression coverage for impacted good/bad/edge scenarios.
4. Changelog/version alignment for release candidates.

### 7.1 PR automation gate

1. `PR Validation` runs `analyze`, `unit`, `integration`, and `e2e` jobs on PR open/update.
2. Only successful workflow runs are eligible for owner PR auto-approval and auto-merge to `main`.
3. Publication remains downstream of merge on `main`, preserving a single gated release path.

## 8. Recommended automation roles

The project now includes dedicated Copilot assets for this model:

- `vulnerability-guardrails` skill for security triage and remediation gating.
- `full-spectrum-test-generation` skill for comprehensive test generation.
- `full-spectrum-test-generator` sub-agent for unit/integration/e2e/UI automation.

These assets are designed to keep quality high while accelerating secure delivery.

# Architecture

`flutter_esptool` is a layered Flutter/Dart package for ESP8266/ESP32 ROM bootloader workflows. The core package is UI-agnostic and talks to serial hardware through an injectable transport interface, making hardware-free tests possible.

## Package Layers

```mermaid
flowchart TB
  Public[flutter_esptool.dart public API]
  App[Application services]
  Domain[Domain contracts]
  Transport[Transport protocol]
  Infra[Infrastructure helpers]
  Models[Models and Result/Error types]
  Serial[platform_serial]
  Device[ESP ROM bootloader / SPI flash]

  Public --> App
  Public --> Domain
  Public --> Models
  App --> Domain
  App --> Transport
  App --> Infra
  App --> Models
  Transport --> Models
  Transport --> Serial
  Infra --> Models
  Serial --> Device
```

| Layer | Path | Responsibility |
| --- | --- | --- |
| Application | `lib/src/application/` | Orchestrates connection, chip detection, flash operations, and info reads. |
| Domain | `lib/src/domain/` | Service interfaces and domain contracts. |
| Transport | `lib/src/transport/` | ESP packet encoding, SLIP framing, response parsing, serial error mapping. |
| Infrastructure | `lib/src/infrastructure/` | Flash image parsing/building, partition parsing, compression helpers. |
| Models | `lib/src/models/` | Commands, config, progress, result/error, chip/flash metadata. |

## Service dependency graph

```mermaid
classDiagram
  class ConnectionService {
    +connect(EspConfig) Result~void~
    +disconnect() Future~void~
  }
  class ChipDetectionService {
    +detect() Result~EspChipInfo~
  }
  class InfoService {
    +getChipInfo() Result~EspChipInfo~
    +getMac() Result~String~
    +getFlashId() Result~EspFlashInfo~
  }
  class FlashService {
    +writeFlash(FlashParameters) Result~void~
    +readFlash(FlashReadParameters) Result~Uint8List~
    +eraseFlash(offset,size) Result~void~
    +md5Flash(offset,size) Result~String~
  }
  class EspTransportInterface {
    +open(EspConfig)
    +close()
    +sendCommand(EspCommand)
    +resetToBootloader()
  }

  ConnectionService --> EspTransportInterface
  ChipDetectionService --> EspTransportInterface
  InfoService --> ChipDetectionService
  InfoService --> EspTransportInterface
  FlashService --> EspTransportInterface
```

## End-to-End Connection and Info Flow

```mermaid
sequenceDiagram
  participant Client as UI / CLI / Test
  participant Conn as ConnectionService
  participant Detect as ChipDetectionService
  participant Info as InfoService
  participant Tx as EspTransport
  participant ESP as ESP ROM

  Client->>Conn: connect(EspConfig)
  Conn->>Tx: open(serial config)
  Conn->>Tx: sync command, with retries
  Tx->>ESP: SLIP-encoded SYNC
  ESP-->>Tx: SYNC response(s)
  Tx-->>Conn: Success
  Conn-->>Client: Result.success

  Client->>Detect: detect()
  Detect->>Tx: READ_REG magic
  Tx->>ESP: READ_REG 0x40001000
  ESP-->>Tx: magic value
  Detect->>Tx: READ_REG MAC/eFuse words
  ESP-->>Tx: MAC words
  Detect-->>Client: EspChipInfo

  Client->>Info: getFlashId()
  Info->>Detect: detect()
  Info->>Tx: SPI attach + SPI register flow
  ESP-->>Tx: JEDEC flash ID
  Info-->>Client: EspFlashInfo
```

## Flash Write Flow

```mermaid
flowchart TD
  Start([writeFlash]) --> Pad[Pad image to block size]
  Pad --> Split[Split into blocks]
  Split --> Compress{compress?}
  Compress -- yes --> Deflate[Compress each block]
  Compress -- no --> Raw[Use raw block data]
  Deflate --> Begin[FLASH_DEFL_BEGIN]
  Raw --> BeginRaw[FLASH_BEGIN]
  Begin --> Blocks[Send FLASH_DEFL_DATA blocks]
  BeginRaw --> BlocksRaw[Send FLASH_DATA blocks]
  Blocks --> End[FLASH_DEFL_END]
  BlocksRaw --> EndRaw[FLASH_END]
  End --> Verify{verify?}
  EndRaw --> Verify
  Verify -- yes --> MD5[FLASH_MD5 and compare]
  Verify -- no --> Done([Success])
  MD5 --> Match{match?}
  Match -- yes --> Done
  Match -- no --> Failure([flashVerifyFailed])
```

## Transport Boundary

`EspTransport` is the protocol boundary:

- builds command packets with little-endian fields;
- wraps packets using SLIP (`SlipCodec`);
- accumulates partial reads until a complete frame is available;
- ignores stale opcode responses until the expected command response arrives;
- parses frame payloads into typed `EspResponse`;
- maps `platform_serial` errors to package-level `EspError` values.

```mermaid
flowchart LR
  Command[EspCommand] --> Packet[8-byte header + payload]
  Packet --> Slip[SLIP encode]
  Slip --> SerialWrite[Serial write + flush]
  SerialRead[Serial read chunks] --> Buffer[Read buffer]
  Buffer --> Frame[Complete SLIP frame]
  Frame --> Parse[Parse EspResponse]
  Parse --> Match{opcode matches?}
  Match -- yes --> Return[Return response]
  Match -- no --> SerialRead
```

## Error and Result Strategy

```mermaid
flowchart TD
  Operation[Service operation] --> Try[Try protocol operation]
  Try --> OK{Device accepted?}
  OK -- yes --> Success[Success<T>]
  OK -- no --> Failure[Failure<T> with EspError]
  Try --> Exception{Exception?}
  Exception -- EspError --> Failure
  Exception -- SerialError --> Map[Map to EspErrorType]
  Exception -- Other --> Defensive[Defensive typed EspError]
  Map --> Failure
  Defensive --> Failure
```

- Service methods return `Result<T>` (`Success<T>` / `Failure<T>`).
- Operation failures are represented as typed `EspError` with `EspErrorType`.
- Transport-level exceptions are mapped to package-level errors.

## Testing Strategy

- Unit tests target codec, parser, model, and defensive branch behavior.
- Integration/e2e tests use scripted transport responses to validate protocol workflows without hardware.
- Hardware tests are opt-in and require an explicit port.
- Root package coverage is expected to stay at 100% for the current instrumented production lines.

```mermaid
flowchart LR
  Unit[Unit tests] --> Coverage[coverage/lcov.info]
  Integration[Scripted transport tests] --> Coverage
  Hardware[Opt-in hardware tests] --> Evidence[Hardware evidence]
  Coverage --> Gate{100% root package coverage}
  Gate -- yes --> Merge[Ready]
  Gate -- no --> MoreTests[Add focused tests]
```

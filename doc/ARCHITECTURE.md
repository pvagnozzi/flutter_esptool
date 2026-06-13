# Architecture

## Package Layers

`flutter_esptool` is organized with explicit responsibilities:

- `lib/src/application/`: orchestration services (`ConnectionService`, `ChipDetectionService`, `FlashService`, `InfoService`)
- `lib/src/domain/`: service interfaces and domain contracts
- `lib/src/transport/`: serial protocol transport and SLIP framing
- `lib/src/infrastructure/`: image parsing, partition parsing, compression helpers
- `lib/src/models/`: protocol models, result/error types, progress/config types

## End-to-End Flow

1. `ConnectionService.connect(EspConfig)` opens serial, toggles bootloader lines, and performs sync retries.
2. `ChipDetectionService.detect()` reads magic register and resolves the ESP family.
3. `InfoService` exposes chip metadata, MAC address, and flash ID reads.
4. `FlashService.writeFlash(FlashParameters)` performs flash begin/data/end operations and optional MD5 verification.

## Transport Boundary

`EspTransport` is the protocol boundary:

- builds command packets with little-endian fields
- wraps packets using SLIP (`SlipCodec`)
- accumulates partial reads until a complete frame is available
- parses frame payloads into typed `EspResponse`

All high-level services depend on `EspTransportInterface`, enabling transport simulation in tests.

## Error and Result Strategy

- Service methods return `Result<T>` (`Success<T>` / `Failure<T>`)
- Operation failures are represented as typed `EspError` with `EspErrorType`
- Transport-level exceptions are mapped to package-level errors

## Testing Strategy

- Unit tests target codec, parser, and model behavior.
- Integration/e2e tests use scripted transport responses to validate protocol workflows without hardware.

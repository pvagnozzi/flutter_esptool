## 0.1.2

### Pub.dev Quality Cleanup

#### Changed
- Shortened the package description to satisfy pub.dev search-result metadata guidance.
- Updated the documentation URL to the reachable `dev` branch documentation path.
- Upgraded Flutter lint rules in the root package and example app to remove analyzer/lint warnings.
- Added `.pubignore` exclusions for local runtime, coverage, build, and generated ephemeral artifacts.

#### Verified
- `flutter analyze --fatal-infos --fatal-warnings`
- `flutter test --coverage`
- `dart run tool/coverage_gate.dart --lcov coverage/lcov.info --min-lines 100`
- `flutter pub publish --dry-run`

## 0.1.1

### Professional Hardening and Control Signals

#### Added
- Public `SerialControlSignals` model for RTS, CTS, DTR, DSR and DCD status snapshots.
- `SerialPort.getControlSignals()` and `SerialPort.getCts()` APIs.
- Linux MethodChannel support for reading control signals and setting DTR/RTS through the existing native `getControlSignals` and `setControlSignals` handlers.
- Windows FFI support for reading CTS/DSR/DCD status and tracked DTR/RTS output state.
- 100% line-coverage gate for the configured test coverage scope.
- Professional GitFlow branch-protection ruleset, release manager agent, Copilot quality gate skill, repository templates and cross-platform development setup scripts.

#### Changed
- Release publishing now targets pub.dev trusted publishing/OIDC and creates GitHub tags/releases only after successful publish.
- Documentation now includes Mermaid diagrams for architecture, quality gate, GitFlow and release workflows.

#### Verified
- `flutter analyze --fatal-infos --fatal-warnings`
- `flutter test --coverage`
- `dart run tool/coverage_gate.dart --lcov coverage/lcov.info --min-lines 100`
- `flutter pub publish --dry-run`

## 0.1.0

### First Release - Core Functionality

#### Added
- Unified `SerialPort` interface for serial communication
- `SerialManager` for centralized port management
- Support for synchronous and asynchronous reading
- Support for binary and textual data
- Data streams for continuous asynchronous reading
- Flexible configuration (baud rate, data bits, stop bits, parity, flow control)
- Configurable timeouts for read and write operations
- Robust error handling with specific error types:
  - `portNotFound`
  - `portAlreadyOpen`
  - `portClosed`
  - `configurationError`
  - `timeout`
  - `platformUnavailable`
  - `ioError`
  - `permissionDenied`
  - `bufferOverflow`
  - `unknown`
- Example app with language selection (15 languages with flags 🇬🇧 🇮🇹 🇫🇷 etc.)
- Light/Dark/System theme support
- Git Flow workflow with GitVersion configuration
- GitHub Actions CI/CD workflows:
  - Automated testing on PR
  - Automated pub.dev publishing with Google OAuth

#### Supported Platforms
- Windows (FFI implementation)
- Linux (FFI implementation)
- macOS (FFI implementation)
- Android (platform channel + OTG support)
- iOS (platform channel + OTG support)

#### Port Information
- List of available ports
- Device details (vendor ID, product ID, serial number)
- Port status (open/closed)

#### Testing
- Unit tests for core logic
- Integration tests for platform-specific behavior
- E2E tests with happy path, failure path, and edge cases
- Mock serial ports for testing

#### Documentation
- Comprehensive architecture documentation
- Platform-specific implementation guides
- Git Flow and release process documentation
- Google OAuth setup for automated publishing

#### Notes
- First stable release - production-ready
- Ready for use on all supported platforms

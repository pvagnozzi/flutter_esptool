# Contributing to flutter_esptool

Thank you for your interest in contributing! This guide explains how to report issues, propose changes, and submit pull requests that meet professional standards.

---

## Table of Contents

1. [How to contribute](#how-to-contribute)
2. [Fork → branch → PR flow](#fork--branch--pr-flow)
3. [Code style](#code-style)
4. [Test requirements](#test-requirements)
5. [Commit message format](#commit-message-format)
6. [Documentation standards](#documentation-standards)

---

## How to contribute

- **Bug reports** – Open an issue at <https://github.com/pvagnozzi/flutter_esptool/issues> with a minimal reproduction and expected behavior.
- **Feature requests** – Open an issue describing the use-case, API design, and expected behavior before starting implementation.
- **Documentation improvements** – Feel free to open a PR directly for typo fixes or clarifications.
- **Code contributions** – Follow the flow below and ensure all test tiers pass.

---

## Fork → branch → PR flow

This project follows a simplified **Gitflow** model:

| Branch pattern | Purpose |
|----------------|----------|
| `main`         | Latest stable release (auto-publishes to pub.dev on PR merge) |
| `develop`      | Integration branch for the next release |
| `feat/*`       | New features |
| `fix/*`        | Bug fixes |
| `docs/*`       | Documentation-only changes |
| `chore/*`      | Tooling, CI, dependency updates |

### Step-by-step

1. **Fork** the repository on GitHub.
2. **Clone** your fork and add the upstream remote:
   ```bash
   git clone https://github.com/<your-handle>/flutter_esptool.git
   cd flutter_esptool
   git remote add upstream https://github.com/pvagnozzi/flutter_esptool.git
   ```
3. **Sync** with `develop` (or `main` for hotfixes):
   ```bash
   git fetch upstream
   git checkout -b feat/my-feature upstream/develop
   ```
4. **Make changes**, following the [code style](#code-style) and [test requirements](#test-requirements).
5. **Push** your branch and open a **Pull Request** targeting `develop` (or `main` for hotfixes).
6. Ensure all CI checks pass before requesting review.

---

## Code style

### Formatting

- Format all Dart code with `dart format`:
  ```bash
  dart format lib/ test/ example/
  ```
- Run the static analyser before every commit:
  ```bash
  flutter analyze
  ```
  The project enforces the rules defined in `analysis_options.yaml`.

### Naming & Conventions

- Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart) style guide.
- Use descriptive names for classes, methods, and variables.
- Use `private` for internal implementation details (prefix with `_`).
- Prefer `final` over `var` for clarity.

### Comments

- Add **English dartdoc comments** (`///`) to every public class, constructor, method, and field.
- Include parameter descriptions, return value documentation, and usage examples where helpful.
- Use inline comments (`//`) to explain complex logic within function bodies.
- Keep comments up-to-date when code changes.

Example:

```dart
/// Writes firmware to the flash memory at the specified offset.
///
/// Supports optional compression (zlib) and on-the-fly verification (MD5).
/// When a flasher stub is loaded, encryption can be performed on-the-fly
/// by the device itself.
///
/// Returns [Result<void>] with either success or an [EspError] containing
/// the failure reason and optional stack trace.
///
/// Throws [ArgumentError] if [params.offset] or [params.data] are invalid.
///
/// Example:
/// ```dart
/// final result = await flash.writeFlash(
///   FlashParameters(
///     offset: 0x1000,
///     data: firmware,
///     compress: true,
///     verify: true,
///   ),
/// );
/// ```
Future<Result<void>> writeFlash(FlashParameters params) async {
  // ...
}
```

---

## Test requirements

All three test tiers must pass before merging:

| Tier | Command | Notes |
|------|---------|-------|
| Unit | `flutter test test/unit` | No hardware or mocks required |
| Integration | `flutter test test/integration` | Mock transport layer |
| E2E | `flutter test test/e2e` | Mock device simulation |

Run the full suite:

```bash
flutter test --coverage
```

### New Code Requirements

- Write **unit tests** for all new public methods (happy path + edge cases).
- Write **integration tests** if a new service or transport interaction is added.
- Update **e2e scenarios** if the flash workflow or chip detection changes.
- Maintain or improve **code coverage** (target: ≥80% for new code).

Coverage reports are generated to `coverage/lcov.info` and can be viewed in HTML:

```bash
dart pub global activate lcov
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html  # macOS
# or xdg-open coverage/html/index.html  # Linux
# or start coverage/html/index.html  # Windows
```

---

## Commit message format

This project uses **Conventional Commits** (<https://www.conventionalcommits.org/>):

```
<type>(<scope>): <short summary>

[optional body]

[optional footer(s)]
```

### Types

| Type | When to use |
|------|-------------|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation-only change |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or correcting tests |
| `chore` | Build process, CI, dependency updates |
| `perf` | Performance improvement |

### Examples

```
feat(transport): add baud-rate auto-detection for ESP32-C3

Implements automatic detection of optimal baud rate by testing
common rates in descending order of speed.

feat(flash): support on-the-fly encryption in ROM-loader mode

When flash-encryption is active and the ROM bootloader is in use,
enable transparent encryption during flash writes by setting the
encrypted flag on FLASH_BEGIN.

fix(flash): round erase size up to sector boundary

Previously, erase requests with unaligned sizes could corrupt
adjacent sectors. Now the size is automatically rounded up to
the nearest 4KB sector boundary.

docs(readme): add platform support table and architecture diagram

chore(deps): bump flutter to 3.16.0 and crypto to 3.0.2
```

### Breaking Changes

Breaking changes must include `BREAKING CHANGE:` in the footer and `!` after the type:

```
feat!: rename EspConfig.port to EspConfig.portName

BREAKING CHANGE: the `port` field has been renamed to `portName`
for consistency with the platform_serial API.
```

---

## Documentation standards

### README.md

- Keep the README concise but comprehensive.
- Include: description, features, installation, quick start, API reference, architecture overview.
- Add badges for version, license, CI status, and code quality.
- Link to external resources (pub.dev, official docs).

### Dartdoc Comments

- Use proper **markdown** formatting in doc comments:
  ```dart
  /// Computes the MD5 hash of a flash region using the device's
  /// on-board FLASH_MD5 command.
  ///
  /// The device performs the computation, so this is fast and does not
  /// require loading the flasher stub.
  ///
  /// **Parameters:**
  /// - [offset]: Flash address (must be 4-byte aligned)
  /// - [size]: Number of bytes to hash (must be ≥4 bytes)
  ///
  /// **Returns:**
  /// A 16-byte MD5 digest wrapped in [Result<Uint8List>].
  ///
  /// **Throws:** [EspError] with type [EspErrorType.flashReadFailed] on error.
  ///
  /// **Example:**
  /// ```dart
  /// final hashResult = await flash.computeFlashMd5(offset: 0, size: 8192);
  /// hashResult.fold(
  ///   (digest) => print('MD5: ${digest.toHexString()}'),
  ///   (err) => print('Error: ${err.message}'),
  /// );
  /// ```
  Future<Result<Uint8List>> computeFlashMd5({
    required int offset,
    required int size,
  }) async { ... }
  ```

### CHANGELOG.md

Maintain a changelog using [Keep a Changelog](https://keepachangelog.com/) format:

```markdown
## [0.2.0] - 2026-09-15

### Added
- Professional documentation standards
- Enhanced CI/CD pipeline with artifact publishing
- Comprehensive inline comments for all public members
- Support for Flutter 3.16.0 and Dart 3.4.0

### Changed
- Upgraded flutter_lints to ^4.0.0
- Updated minimum Flutter version to 3.16.0
- Improved error messages for better debugging

### Fixed
- Circuit breaker state transitions under concurrent requests
- SLIP frame decoding edge case with escape sequences

### Deprecated
- Legacy `port` field in EspConfig (use `portName` instead)

### Removed
- Support for Dart <3.4.0
```

---

## Pull Request Checklist

Before submitting a PR, ensure:

- [ ] Branch name follows the pattern: `feat/`, `fix/`, `docs/`, `chore/`
- [ ] All changes are formatted with `dart format`
- [ ] No analysis warnings: `flutter analyze` passes
- [ ] All tests pass: `flutter test --coverage`
- [ ] Code coverage maintained or improved
- [ ] Dartdoc comments added to public members
- [ ] CHANGELOG.md updated with brief description
- [ ] Commit messages follow Conventional Commits format
- [ ] PR description references related issues (e.g., "Fixes #123")
- [ ] No unrelated changes included in the PR

---

## Review Process

Once you open a PR:

1. **Automated checks** run (CI/CD pipeline, code analysis, tests).
2. **Code review** by maintainers (may request changes).
3. **Approval** once all checks pass and feedback is addressed.
4. **Auto-merge** happens automatically on main branch (for owner PRs).
5. **Release** is published to pub.dev automatically on merge to main.

---

## Questions?

Feel free to open a discussion or issue if you have questions about contributing!

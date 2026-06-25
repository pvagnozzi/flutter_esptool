# Contributing to flutter_esptool

Thank you for your interest in contributing! This guide explains how to report
issues, propose changes, and submit pull requests.

---

## Table of Contents

1. [How to contribute](#how-to-contribute)
2. [Fork → branch → PR flow](#fork--branch--pr-flow)
3. [Code style](#code-style)
4. [Test requirements](#test-requirements)
5. [Commit message format](#commit-message-format)

---

## How to contribute

- **Bug reports** – open an issue at
  <https://github.com/pvagnozzi/flutter_esptool/issues> with a minimal
  reproduction.
- **Feature requests** – open an issue describing the use-case and expected
  API before starting implementation.
- **Documentation improvements** – feel free to open a PR directly for
  typo fixes or clarifications.
- **Code contributions** – follow the flow below.

---

## Fork → branch → PR flow

This project follows a simplified **Gitflow** model:

| Branch pattern | Purpose |
|----------------|---------|
| `main`         | Latest stable release |
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
3. **Sync** with `develop`:
   ```bash
   git fetch upstream
   git checkout -b feat/my-feature upstream/develop
   ```
4. **Make changes**, following the [code style](#code-style) and
   [test requirements](#test-requirements).
5. **Push** your branch and open a **Pull Request** targeting `develop`.
6. Ensure all CI checks pass before requesting review.

---

## Code style

- Format all Dart code with `dart format`:
  ```bash
  dart format lib/ test/
  ```
- Run the static analyser before every commit:
  ```bash
  flutter analyze
  ```
  The project enforces the rules defined in `analysis_options.yaml`.
- Follow the [Effective Dart](https://dart.dev/guides/language/effective-dart)
  style guide.
- Add `/// dartdoc` comments to every public class, constructor, method, and
  field.

---

## Test requirements

All three test tiers must pass before merging:

| Tier | Command | Notes |
|------|---------|-------|
| Unit | `flutter test test/unit` | No hardware required |
| Integration | `flutter test test/integration` | Mock transport |
| E2E | `flutter test test/e2e` | Mock device; no real hardware needed |

Run the full suite:
```bash
flutter test
```

New code must include:
- Unit tests for all new public methods (edge cases + happy path).
- Integration tests if a new service or transport interaction is added.
- Updated e2e scenarios if the flash workflow changes.

Coverage reports are written to `reports/tests/<timestamp>/` by the CI scripts
in `scripts/`.

---

## Commit message format

This project uses **Conventional Commits**
(<https://www.conventionalcommits.org/>):

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

fix(flash): round erase size up to sector boundary

docs(readme): add platform support table

chore(deps): bump mocktail to 1.0.4
```

Breaking changes must include `BREAKING CHANGE:` in the footer and `!` after
the type:

```
feat!: rename EspConfig.port to EspConfig.portName

BREAKING CHANGE: the `port` field has been renamed to `portName` for clarity.
```

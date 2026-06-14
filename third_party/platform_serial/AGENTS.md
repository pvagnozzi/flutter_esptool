# Agent Instructions — platform_serial

This repository is a Flutter plugin for serial communication across Windows, Linux, macOS, Android and iOS.

## Mandatory workflow

1. Work from a feature branch; never push directly to `main`, `develop`, or `dev`.
2. Before editing, identify whether the change touches Dart API, native platform code, CI/release automation, or documentation.
3. Keep public Dart APIs documented with `///` comments and preserve typed `SerialError` failures.
4. Run the smallest targeted test first, then the full quality gate before handoff:
   ```bash
   flutter pub get
   flutter analyze --fatal-infos --fatal-warnings
   flutter test --coverage
   dart run tool/coverage_gate.dart --lcov coverage/lcov.info --min-lines 100
   ```
5. For release changes, also run:
   ```bash
   flutter pub publish --dry-run
   ```

## Architecture guardrails

- Public exports belong in `lib/platform_serial.dart`.
- `SerialManager` owns port lifecycle and the open-port registry.
- `SerialPort` owns stream translation and delegates platform I/O to `SerialPlatformInterface`.
- Platform-specific native behavior belongs under the matching platform directory or `lib/src/platform/*_impl.dart`.
- Do not add hardware-dependent tests to the default suite; use mocks/fakes unless a platform workflow explicitly provisions devices.

## Release and branch policy

- `main`, `develop`, and transitional `dev` branches must be protected by GitHub rulesets.
- Publishing happens only after a PR is merged into `main` or by a protected manual dispatch.
- Pub.dev publishing must use trusted publishing/OIDC; do not add long-lived pub.dev or Google service-account JSON secrets.
- Create GitHub tags/releases only after `flutter pub publish --dry-run`, tests, coverage, and actual pub.dev publication succeed.

## Documentation expectations

- Update `README.md` for user-facing behavior.
- Update `doc/` for architecture, GitFlow, release, and operational workflows.
- Add Mermaid diagrams when documenting process or architecture changes.

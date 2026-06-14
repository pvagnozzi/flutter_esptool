# Workflows and Automation

This document describes the development workflows provided by `flutter_esptool`.

## Repository workflow map

```mermaid
flowchart TD
  Dev[Developer workstation] --> Setup[setup-dev script]
  Setup --> Toolchain[Git + VS Code + Android Studio + Flutter + SDKs]
  Toolchain --> Doctor[flutter doctor]
  Doctor --> Tests[run-tests script]
  Doctor --> Build[build script]
  Tests --> TestReports[reports/tests/timestamp]
  Build --> BuildReports[reports/builds/timestamp]
  Tests --> Coverage[coverage/lcov.info]
  Coverage --> QualityGate{100% root package coverage?}
  QualityGate -- yes --> Ready[Ready for review/release]
  QualityGate -- no --> AddTests[Add focused tests]
  AddTests --> Tests
```

## Setup workflow

All platform setup scripts share the same intent and behavior:

- install or update the project development toolchain;
- configure shell startup for Oh My Posh with the `M365Princess` theme;
- remain idempotent so they can be re-run safely;
- elevate privileges only when package installation requires it.

```mermaid
sequenceDiagram
  participant User
  participant Script as setup-dev
  participant PM as Package manager
  participant Shell as Shell profile
  participant Flutter

  User->>Script: run setup-dev
  Script->>Script: parse help/options
  Script->>Script: check/elevate privileges if required
  Script->>PM: install or update Git, VS Code, Android Studio, SDKs
  PM-->>Script: installed/current
  Script->>Shell: write managed Oh My Posh block
  Script->>Flutter: flutter doctor
  Flutter-->>Script: environment diagnostics
  Script-->>User: completion summary
```

## Test workflow

`run-tests` creates a timestamped report folder and runs the same logical test plan on each host:

1. root package tests, with coverage by default;
2. CLI example tests;
3. UI example tests;
4. optional hardware integration tests when explicitly requested.

```mermaid
flowchart LR
  Start([run-tests]) --> Root[flutter test --coverage]
  Root --> Copy[copy lcov.info to report]
  Copy --> CLI[example/esptool_cli flutter test]
  CLI --> UI[example/esptool_ui flutter test]
  UI --> Hardware{Include hardware?}
  Hardware -- no --> Summary[summary.md]
  Hardware -- yes --> HW[hardware integration test]
  HW --> Summary
  Summary --> Exit{Failures?}
  Exit -- no --> Pass([exit 0])
  Exit -- yes --> Fail([exit 1])
```

## Build workflow

`build` attempts every Flutter target that can be built on the current host and records unsupported targets as skipped.

```mermaid
flowchart TD
  Start([build]) --> Examples{Example app}
  Examples --> CLI[esptool_cli]
  Examples --> UI[esptool_ui]
  CLI --> Targets{Target}
  UI --> Targets
  Targets --> Web[web]
  Targets --> Desktop[host desktop target]
  Targets --> Android[android-apk]
  Targets --> Apple[macos / ios-no-codesign]
  Web --> Report[reports/builds/timestamp]
  Desktop --> Report
  Android --> Report
  Apple --> HostCheck{macOS host?}
  HostCheck -- yes --> Report
  HostCheck -- no --> Skipped[record skipped]
  Skipped --> Report
```

## Host capability matrix

```mermaid
quadrantChart
  title Flutter build target host availability
  x-axis Requires current host --> Cross-host friendly
  y-axis Mobile --> Desktop/Web
  quadrant-1 Cross-host desktop/web
  quadrant-2 Host-specific desktop
  quadrant-3 Host-specific mobile
  quadrant-4 Cross-host mobile
  Web: [0.88, 0.82]
  Android APK: [0.80, 0.25]
  Windows: [0.18, 0.75]
  Linux: [0.22, 0.70]
  macOS: [0.18, 0.68]
  iOS no-codesign: [0.20, 0.20]
```

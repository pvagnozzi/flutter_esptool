# Publishing and Release

## pub.dev Prerequisites

1. Ensure package metadata in `pubspec.yaml` is valid (`name`, `description`, `homepage`, `repository`, `issue_tracker`, `version`).
2. Ensure `README.md`, `CHANGELOG.md`, and `LICENSE` are present at repository root.
3. Ensure tests and analyzer pass.

## Local Validation

```bash
flutter pub get
flutter analyze
flutter test
dart pub publish --dry-run
```

## GitHub Workflow Automation

This repository contains:

- `.github/workflows/ci-pr.yml` for test/analyze on pull request activity
- `.github/workflows/release-publish.yml` for release + pub.dev publication when a pull request into `main` is merged

## Required Secrets

- `PUB_DEV_PUBLISH_TOKEN`: token used to authenticate `dart pub publish`
- `GITHUB_TOKEN`: provided by GitHub Actions for release/tag operations

## Release Versioning

- Package semantic version is defined in `pubspec.yaml`
- GitVersion conventions are in `GitVersion.yml`
- Release tags follow `v<package-version>`

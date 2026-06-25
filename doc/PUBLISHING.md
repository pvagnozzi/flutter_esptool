# Publishing and Release

## pub.dev Prerequisites

1. Ensure package metadata in `pubspec.yaml` is valid (`name`, `description`, `homepage`, `repository`, `issue_tracker`, `version`).
2. Ensure `README.md`, `CHANGELOG.md`, and `LICENSE` are present at repository root.
3. Ensure tests and analyzer pass.

## Local Validation

```bash
flutter pub get
flutter analyze
flutter test test\unit
flutter test test\integration
flutter test test\e2e
dart pub publish --dry-run
```

## GitHub Workflow Automation

This repository contains:

- `.github/workflows/ci-pr.yml` for analyzer + unit/integration/e2e quality gates on pull request activity
- `.github/workflows/owner-pr-auto-approve-merge.yml` for owner-only auto-approval and auto-merge after green PR checks
- `.github/workflows/release-publish.yml` for release + pub.dev publication when a pull request into `main` is merged

## Trusted Publishing (OIDC)

- Configure GitHub as a trusted publisher in pub.dev for this package.
- The workflow requires `id-token: write` and uses OIDC, so long-lived pub.dev API tokens are not required.
- `GITHUB_TOKEN` is still used for release/tag operations.

## Release Versioning

- Package semantic version is defined in `pubspec.yaml`
- GitVersion conventions are in `GitVersion.yml`
- Release tags follow `v<package-version>`

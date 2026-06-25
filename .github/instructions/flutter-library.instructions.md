---
description: Flutter/Dart package implementation conventions for flutter_esptool
applyTo: "lib/**/*.dart,test/**/*.dart,example/**/*.dart"
---

# Flutter package conventions

- Keep APIs `Result<T>`-based in service layers; do not switch to exception-only flow.
- Maintain typed `EspErrorType` mapping when adding new failure paths.
- Keep protocol serialization little-endian and verify packet structure in tests.
- Prefer transport abstraction (`EspTransportInterface`) in services and tests.
- For tests, use scripted or mocked transport implementations, not physical serial devices.

## Automated Publishing

The `flutter_esptool` publish pipeline follows a **gitflow → pub.dev** model
managed entirely through GitHub Actions with OIDC trusted publishing (no
long-lived `PUB_CREDENTIALS` secrets are stored in the repository).

### Flow overview

```
feature/* ──┐
             ▼
          develop  ──── integration CI (analyze + unit + integration + e2e)
             │
             │  (release branch cut)
             ▼
        release/x.y.z ── pre-release CI gate (same scopes, strict)
             │
             │  (PR → main)
             ▼
            main  ──── publish workflow triggers
             │              └─ dart pub publish (OIDC, no token)
             │              └─ GitHub Release created with CHANGELOG entry
             ▼
           tag vX.Y.Z
```

### Rules

1. **Never publish from `develop` or feature branches.** The publish
   workflow is triggered only by pushes to `main` that carry a version tag
   (`v*.*.*`).
2. **Version bump before merging the release branch.** Update `pubspec.yaml`
   `version` and add a `CHANGELOG.md` entry as part of the release branch,
   not as a separate hotfix after merge.
3. **Trusted publishing (OIDC) only.** Configure the pub.dev publisher to
   accept tokens from the repository's Actions OIDC provider. This removes
   the need to rotate `PUB_CREDENTIALS` secrets.
4. **Publish is downstream from all CI gates.** The `release-publish.yml`
   workflow has a `needs:` dependency on the CI validation job; a failing
   test scope blocks publication automatically.
5. **Dry-run check on every PR.** The CI pipeline runs
   `dart pub publish --dry-run` to catch pub.dev validation errors
   (missing dartdoc, SDK constraint issues) before merge.

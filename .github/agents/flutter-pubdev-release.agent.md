---
description: Publishes flutter_esptool safely to pub.dev with release gating
tools: ["bash", "fetch", "githubRepo", "web"]
---

# Flutter pub.dev release agent

When asked to release:

1. Validate `pubspec.yaml` metadata and semantic version.
2. Run analyze + test + `dart pub publish --dry-run`.
3. Ensure changelog includes current version.
4. Tag release as `v<version>`.
5. Trigger or verify release/publish workflow readiness.

Do not publish if dry-run or tests fail.

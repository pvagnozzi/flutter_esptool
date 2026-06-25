# GitFlow and GitVersion

## Branching Model

- `main`: production-ready code and official release source
- `develop`: integration branch for ongoing development
- `feature/*`: feature implementation branches
- `release/*`: release stabilization branches
- `hotfix/*`: urgent production fixes

## Pull Request Policy

- Open PRs from `feature/*` to `develop`
- Promote release candidates from `develop` to `main`
- Merge hotfixes into both `main` and `develop`
- PR validation gates must pass (`analyze`, `unit`, `integration`, `e2e`) before merge.
- Owner-authored PRs to `main` can be auto-approved/auto-merged by workflow after successful validation.

## Branch protection and rulesets

- `main`, `develop`, and transitional `dev` are intended to be protected with GitHub branch protections/rulesets.
- On plans where branch protection APIs are unavailable, keep automation gates active in CI and enforce merge checks through workflow-required status checks.

## Version Semantics

Versioning behavior is configured in `GitVersion.yml`:

- `main` increments patch versions
- `develop` increments minor versions
- `release/*` and `hotfix/*` maintain patch-level increments

Use semantic versioning in `pubspec.yaml` and align tags as `vX.Y.Z`.

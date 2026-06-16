---
description: GitOps branch gating, PR validation, and security-aware merge/publish policy
applyTo: ".github/workflows/**/*.yml,.github/workflows/**/*.yaml,.github/**/*.md,doc/**/*.md"
---

# GitOps security and testing instructions

- Keep PR validation split by scope (`analyze`, `unit`, `integration`, `e2e`) so failed quality areas are explicit.
- Auto-approval/merge automation is allowed only after successful PR validation and only for owner-authored PRs to `main`.
- Never bypass failing tests to publish; publish workflows must remain downstream from merge on `main`.
- Prefer trusted publishing (OIDC) for pub.dev; avoid long-lived publish credentials in repository secrets.
- Document any limitations in branch protection/ruleset APIs and preserve equivalent workflow-level gates.

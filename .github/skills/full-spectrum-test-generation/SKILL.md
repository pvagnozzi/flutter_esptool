---
name: full-spectrum-test-generation
description: Generate and maintain comprehensive test suites (unit, integration, e2e, UI) with good/bad/edge coverage.
---

# Full-spectrum test generation skill

Use this skill when tasks require:

- generating missing tests across package and examples;
- expanding coverage for complex protocol flows;
- validating UI states and error presentations;
- enforcing good-path, bad-path, and edge-case confidence.

Coverage expectations:

- unit tests for logic branches and boundaries;
- integration tests for service + transport interactions;
- e2e/scripted-flow tests for end-to-end command sequencing;
- UI widget tests for user-visible states and transitions.

Expected outputs:

- test matrix by file/workflow and test type;
- generated or updated tests with deterministic fixtures;
- explicit assertions on bytes/protocol fields where applicable;
- clear gap report for any intentionally deferred tests.
- execution evidence for `flutter test test\unit`, `flutter test test\integration`, and `flutter test test\e2e`.

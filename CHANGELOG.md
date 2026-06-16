## 0.1.3

- Updated `platform_serial` dependency to `^0.1.2` (latest published version).
- Hardened package metadata for pub.dev (`description`, `homepage`, `repository`, `issue_tracker`).
- Strengthened PR quality gates with scoped unit/integration/e2e jobs and owner-only auto-approve/merge on green.
- Updated release workflow for trusted publishing with OIDC and no long-lived pub.dev token secret.
- Expanded project guidance assets (instructions, skills, agents, and MCP configuration) for testing, vulnerability triage, and security workflows.
- Added metadata tests to enforce pubspec dependency and URL consistency.

## 0.1.2

- Renamed the demo app to `esptool_ui`.
- Switched the demo to use `platform_serial` for real serial port access.
- Added flags in the language selector.
- Fixed padding for the last flash block during writes.

## 0.1.1

- Prepared package for pub.dev publishing metadata and MIT licensing.
- Added professional GitHub project automation (CI, release, and publish workflows).
- Added Copilot project assets (instructions, skills, agents, and MCP server configuration).
- Added professional multilingual demo app under `example/esptool_ui`.
- Added editor and repository standards files (`.editorconfig`, `.gitattributes`, `.gitignore`, `GitVersion.yml`).

## 0.1.0

- Initial workspace package with ESP protocol models, services, transport, parsers, and tests.

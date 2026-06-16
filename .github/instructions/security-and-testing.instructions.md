---
description: Security, vulnerability management, and full-spectrum test automation conventions
applyTo: "lib/**/*.dart,test/**/*.dart,example/**/*.dart,.github/workflows/**/*.yml,.github/workflows/**/*.yaml"
---

# Security and testing conventions

- Security-related changes must preserve explicit, typed error propagation (`EspError` + `EspErrorType`).
- Never introduce silent fallbacks for malformed packets, invalid flash boundaries, or parsing failures.
- Validate negative and edge behavior whenever protocol or transport code changes.
- Keep dependency updates auditable: include reason and risk impact in the related PR description.

## Vulnerability handling workflow

1. Identify vulnerable dependency/code path and impacted scope.
2. Add a reproducing test when feasible (failing-first for bad path).
3. Apply the smallest safe remediation.
4. Verify no regression across unit, integration, and e2e scopes.
5. Document residual risk if remediation is partial.

## Test generation coverage policy

- For each changed workflow, ensure coverage for:
  - good path;
  - bad path;
  - edge cases and boundary values.
- Keep hardware-free defaults in automated suites.
- UI changes in `example/esptool_ui` require widget tests and state-transition assertions.
- Prefer behavior assertions over implementation details.

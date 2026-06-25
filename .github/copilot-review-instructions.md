# Copilot Code Review Instructions for `flutter_esptool`

This file documents how to request and use GitHub Copilot for automated
code review on pull requests in the `flutter_esptool` repository.

---

## When to Request a Copilot Review

Request a Copilot review on a PR when:

- The change touches **transport or protocol code** (SLIP framing, packet
  encoding/decoding, serial I/O).
- A **new public API** is introduced (service method, model, typedef).
- The change modifies **error handling** paths or adds new `EspErrorType`
  values.
- A **refactor** spans multiple layers (domain / application / infrastructure).
- You want a quick **null-safety or async-hygiene** scan before human review.
- The PR is authored by an external contributor or a first-time contributor.

---

## How to Request a Copilot Review

Add one of the trigger phrases below as a comment on the PR (or in the PR
description under **Reviewer Notes**):

### General review

```
@copilot Please review this PR for correctness, null safety, and test
coverage according to the project conventions in
.github/copilot-instructions.md.
```

### Focused review requests

| Focus area | Comment to add |
|---|---|
| Null safety | `@copilot Review for null safety: check for unsafe \`!\` casts and uninitialised \`late\` fields.` |
| Async hygiene | `@copilot Check async hygiene: verify every Future is awaited and no fire-and-forget calls are unhandled.` |
| EspResult usage | `@copilot Verify EspResult usage: confirm all fallible methods return \`EspResult<T>\` and no raw exceptions cross service boundaries.` |
| Test coverage | `@copilot Check test coverage: identify public methods lacking unit tests and missing bad-path scenarios.` |
| Resource cleanup | `@copilot Review resource cleanup: verify serial ports are closed in \`finally\` blocks and StreamSubscriptions are cancelled in \`dispose\`.` |
| Dartdoc | `@copilot Check dartdoc completeness: flag public APIs missing \`///\` comments.` |
| Platform compat | `@copilot Review platform compatibility: flag hard-coded paths and \`dart:io\` platform branches.` |
| Security | `@copilot Security review: check for secrets in code, unvalidated inputs in transport/parser, and any dependency with known CVEs.` |

---

## Standard Review Comment Template

Copy and paste this block into your PR description under **Reviewer Notes**
to request a full automated review:

```markdown
### Copilot Review Request

@copilot Please review this pull request against the conventions defined in
`.github/copilot-instructions.md`. Specifically check:

1. **Null safety** — no unsafe `!` casts or uninitialised `late` fields.
2. **Async hygiene** — every `Future` is awaited or explicitly handled.
3. **EspResult pattern** — all fallible methods return `EspResult<T>`.
4. **Resource cleanup** — ports/subscriptions released in `finally`/`dispose`.
5. **Test coverage** — new public methods have at least one unit test.
6. **Dartdoc** — public APIs carry `///` documentation.
7. **Error types** — `EspErrorType` used; no raw `Exception` across layers.
8. **Platform compat** — no platform-specific paths or hard-coded devices.
9. **CHANGELOG** — entry present for user-visible changes.
10. **Breaking change** — noted in commit footer and PR if applicable.
```

---

## Checklist Integration

The standard `.github/pull_request_template.md` already includes the full
10-item checklist. Copilot will cross-reference its review findings against
each checked/unchecked item and highlight discrepancies.

---

## Tips for Effective Copilot Reviews

- **Be specific**: targeted requests (`@copilot Review for null safety`) yield
  more actionable feedback than generic ones.
- **Link context**: if the PR fixes a specific issue, mention the issue number
  so Copilot can focus on the relevant code path.
- **Iterate**: after addressing Copilot's comments, re-request with
  `@copilot Re-review after latest commits` to confirm fixes.
- **Override carefully**: if you dismiss a Copilot suggestion, add an inline
  comment explaining why so the rationale is preserved in the review history.

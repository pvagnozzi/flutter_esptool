## Summary

<!-- REQUIRED: Describe what this PR changes and why. -->
<!-- Include context, motivation, and any relevant issue links. -->

Closes #

---

## Type of Change

<!-- Check all that apply. -->

- [ ] `feat` — new feature or capability
- [ ] `fix` — bug fix
- [ ] `docs` — documentation only
- [ ] `refactor` — code restructure, no behaviour change
- [ ] `test` — new or updated tests only
- [ ] `chore` — tooling, dependencies, CI/CD, or maintenance
- [ ] `ci` — changes to workflow files only

---

## Breaking Changes

- [ ] This PR introduces a **breaking change**

If yes, describe the impact and migration path:

<!-- What breaks, what must callers change, and in which version it lands. -->

---

## Testing

<!-- Confirm which test scopes were run and pass. -->

- [ ] `flutter analyze` — no new warnings or errors
- [ ] `flutter test test/unit` — all unit tests pass
- [ ] `flutter test test/integration` — all integration tests pass
- [ ] `flutter test test/e2e` — all e2e/scripted-flow tests pass
- [ ] New/modified public methods have at least one unit test
- [ ] Bad-path and edge-case coverage added for changed logic
- [ ] Hardware-dependent tests marked with `@Skip('requires hardware')`

---

## pub.dev Impact

- [ ] `CHANGELOG.md` updated with a user-visible entry (if applicable)
- [ ] Public API dartdoc comments updated or added
- [ ] `pubspec.yaml` version bumped if this is a releasable change
- [ ] No new pub.dev warnings (`dart pub publish --dry-run`)

---

## Security Considerations

- [ ] No new secrets, tokens, or credentials introduced
- [ ] Dependency changes reviewed for CVEs and changelog impact
- [ ] Transport / parser / file-handling changes validated for
      malformed-input behaviour
- [ ] Failures mapped to typed `EspErrorType` (no silent fallbacks)

---

## Reviewer Notes

<!-- Optional: anything reviewers should focus on, known limitations,
     follow-up issues, or areas of uncertainty. -->

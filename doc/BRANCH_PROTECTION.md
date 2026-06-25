# Branch Protection — flutter_esptool

## Situazione attuale

Il repository è **privato** su piano **GitHub Free**. Le API di branch
protection (sia le classiche `/branches/{name}/protection` che i nuovi
Rulesets) richiedono **GitHub Pro** o **repository pubblico**.

## Come abilitare la protezione

### Opzione A — Rendere il repository pubblico (gratuito)

1. Settings → Danger Zone → "Change repository visibility" → Public
2. Configurare le regole usando l'API o la UI (vedi sotto).

### Opzione B — Upgrade a GitHub Pro / Team

Attiva i Rulesets su qualsiasi visibilità.

---

## Regole da applicare (una volta sbloccato)

Per ognuno dei branch **`dev`**, **`test`**, **`stable`**, **`main`**:

| Regola | Valore |
|---|---|
| Require PR before merging | ✅ |
| Required approving reviews | 1 |
| Dismiss stale reviews | ✅ |
| Require status checks | `Analyze`, `Unit tests`, `Integration tests`, `E2E tests` |
| Require branches to be up to date | ✅ |
| Restrict who can push | solo il/i maintainer(s) |
| Allow force pushes | ❌ |
| Allow deletions | ❌ |

### Comandi gh CLI (Rulesets — dopo upgrade/pubblica)

```bash
# Esempio per 'main' (ripetere per dev, test, stable)
gh api repos/pvagnozzi/flutter_esptool/rulesets \
  --method POST \
  --field name="protect-main" \
  --field target="branch" \
  --field enforcement="active" \
  --field 'conditions={"ref_name":{"include":["refs/heads/main"],"exclude":[]}}' \
  --field 'rules=[
    {"type":"deletion"},
    {"type":"non_fast_forward"},
    {"type":"pull_request","parameters":{
      "required_approving_review_count":1,
      "dismiss_stale_reviews_on_push":true,
      "require_code_owner_review":false,
      "require_last_push_approval":false,
      "required_review_thread_resolution":false
    }},
    {"type":"required_status_checks","parameters":{
      "strict_required_status_checks_policy":true,
      "required_status_checks":[
        {"context":"Analyze"},
        {"context":"Unit tests (good/bad/edge)"},
        {"context":"Integration tests (good/bad/edge)"},
        {"context":"E2E tests (good/bad/edge)"}
      ]
    }}
  ]'
```

---

## Gitflow — flusso dei merge

```
feat/* ──────▶ dev ──────▶ test ──────▶ stable ──────▶ main
                                                          │
                                                          ▼
                                                     pub.dev publish
                                              (anche da stable per pre-release)
```

### Pubblicazione su pub.dev

| Branch target | GitHub Release | pub.dev |
|---|---|---|
| `dev` | ❌ | ❌ |
| `test` | ❌ | ❌ |
| `stable` | ✅ pre-release | ✅ se versione non già pubblicata |
| `main` | ✅ stable | ✅ se versione non già pubblicata |

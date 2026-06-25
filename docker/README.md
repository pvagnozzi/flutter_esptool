# Docker Analysis Environment — flutter_esptool

A multi-stage Docker image that bundles Flutter, Dart analysis tools,
semgrep, and lcov so every analysis step runs in a reproducible container.

---

## Prerequisites

| Requirement | Minimum version |
|-------------|----------------|
| Docker      | 24.x           |
| Docker Compose (plugin) | v2.x |

---

## Build the image

```sh
docker compose -f docker/docker-compose.yml build
```

This builds the `flutter_esptool_analysis` image using
`docker/Dockerfile` (multi-stage: **base** → **analysis**).

---

## Run the full analysis suite

```sh
docker compose -f docker/docker-compose.yml run --rm full
```

Executes `docker/scripts/full-analysis.sh`, which runs all five
stages in sequence and writes every artefact under `docker/reports/`.

---

## Run individual tasks

| Service    | What it does                              |
|------------|-------------------------------------------|
| `analyze`  | `flutter analyze --no-pub`                |
| `test`     | `flutter test --coverage`                 |
| `coverage` | Generates HTML report from `lcov.info`    |
| `pana`     | `dart run pana` — pub.dev package score   |
| `semgrep`  | Semgrep static security scan              |

```sh
# Examples
docker compose -f docker/docker-compose.yml run --rm analyze
docker compose -f docker/docker-compose.yml run --rm test
docker compose -f docker/docker-compose.yml run --rm coverage
docker compose -f docker/docker-compose.yml run --rm pana
docker compose -f docker/docker-compose.yml run --rm semgrep
```

---

## Output reports

All artefacts are written to `docker/reports/` on the host:

| File                          | Content                        |
|-------------------------------|--------------------------------|
| `reports/analyze.txt`         | Flutter analyzer output        |
| `reports/test.txt`            | Test runner output             |
| `reports/coverage/index.html` | HTML coverage report           |
| `reports/pana.json`           | Pana score (JSON)              |
| `reports/semgrep.json`        | Semgrep findings (JSON)        |

---

## Notes

- The `coverage` service mounts `docker/reports` to
  `/app/coverage/html` inside the container.
- The `full` service mounts `docker/reports` to `/app/reports`.
- All services mount the project root to `/app`, so source changes
  are reflected immediately without rebuilding the image.

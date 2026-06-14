#!/usr/bin/env zsh
#
# SYNOPSIS
#   🧪 Runs flutter_esptool tests and writes a timestamped report.
#
# USAGE
#   ./scripts/macos/run-tests.zsh [--report-dir DIR] [--skip-coverage] [--include-hardware] [--port PORT] [--help]

set -euo pipefail
REPORT_DIR='reports/tests'
SKIP_COVERAGE=0
INCLUDE_HARDWARE=0
PORT='COM22'
usage(){
  cat <<'HELP'
SYNOPSIS
  🧪 Runs flutter_esptool tests and writes a timestamped report.

USAGE
  ./scripts/macos/run-tests.zsh [--report-dir DIR] [--skip-coverage] [--include-hardware] [--port PORT] [--help]
HELP
}
while (( $# )); do
  case "$1" in
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --skip-coverage) SKIP_COVERAGE=1; shift ;;
    --include-hardware) INCLUDE_HARDWARE=1; shift ;;
    --port) PORT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "❌ Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
if [[ -t 1 ]]; then C0=$'\033[0m'; CB=$'\033[36m'; CG=$'\033[32m'; CY=$'\033[33m'; CR=$'\033[31m'; CM=$'\033[35m'; else C0=''; CB=''; CG=''; CY=''; CR=''; CM=''; fi
step(){ printf '\n%s🔷 %s%s\n' "$CB" "$*" "$C0"; }; ok(){ printf '%s✅ %s%s\n' "$CG" "$*" "$C0"; }; warn(){ printf '%s⚠️  %s%s\n' "$CY" "$*" "$C0"; }; err(){ printf '%s❌ %s%s\n' "$CR" "$*" "$C0" >&2; }
ROOT="$(cd "${0:A:h}/../.." && pwd)"; STAMP="$(date +%Y%m%d-%H%M%S)"; RUN_DIR="$ROOT/$REPORT_DIR/$STAMP"; SUMMARY="$RUN_DIR/summary.md"; FAILURES=0
mkdir -p "$RUN_DIR"; printf '# 🧪 Test report\n\nGenerated: %s\n\n| Status | Step | Log |\n| --- | --- | --- |\n' "$(date -Iseconds)" > "$SUMMARY"
run_logged(){ local name="$1" cwd="$2"; shift 2; local log="$RUN_DIR/${name//[^A-Za-z0-9_.-]/_}.log"; step "$name"; printf '   📁 %s\n   ▶ %s\n' "$cwd" "$*"; if (cd "$cwd" && "$@") >"$log" 2>&1; then ok "$name passed"; printf '| ✅ | %s | [%s](%s) |\n' "$name" "$(basename "$log")" "$(basename "$log")" >> "$SUMMARY"; else err "$name failed"; printf '| ❌ | %s | [%s](%s) |\n' "$name" "$(basename "$log")" "$(basename "$log")" >> "$SUMMARY"; FAILURES=$((FAILURES+1)); fi; }
printf '%s╔════════════════════════════════════════════════════════════╗%s\n' "$CM" "$C0"; printf '%s║ 🧪 flutter_esptool test runner                            ║%s\n' "$CM" "$C0"; printf '%s╚════════════════════════════════════════════════════════════╝%s\n' "$CM" "$C0"; printf '%s📊 Report: %s%s\n' "$CB" "$RUN_DIR" "$C0"
if (( SKIP_COVERAGE )); then run_logged root-flutter-test "$ROOT" flutter test; else run_logged root-flutter-test "$ROOT" flutter test --coverage; fi
if (( ! SKIP_COVERAGE )) && [[ -f "$ROOT/coverage/lcov.info" ]]; then cp "$ROOT/coverage/lcov.info" "$RUN_DIR/lcov.info"; printf '\nCoverage file: [lcov.info](lcov.info)\n' >> "$SUMMARY"; fi
run_logged example-cli-flutter-test "$ROOT/example/esptool_cli" flutter test
run_logged example-ui-flutter-test "$ROOT/example/esptool_ui" flutter test
if (( INCLUDE_HARDWARE )); then run_logged example-ui-hardware-test "$ROOT/example/esptool_ui" flutter test -d macos integration_test/esp32_hardware_test.dart --dart-define=RUN_ESP_HARDWARE_TESTS=true --dart-define=ESP_PORT="$PORT"; else warn 'Hardware tests skipped. Use --include-hardware to run them.'; printf '\nHardware tests skipped.\n' >> "$SUMMARY"; fi
printf '\nFailures: %s\n' "$FAILURES" >> "$SUMMARY"; if (( FAILURES == 0 )); then ok "All tests passed. Report: $RUN_DIR"; else err "$FAILURES test step(s) failed. Report: $RUN_DIR"; exit 1; fi

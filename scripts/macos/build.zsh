#!/usr/bin/env zsh
#
# SYNOPSIS
#   🏗️ Builds flutter_esptool example apps and writes a timestamped report.
#
# USAGE
#   ./scripts/macos/build.zsh [--report-dir DIR] [--mode release|debug|profile] [--continue-on-error] [--help]

set -euo pipefail
REPORT_DIR='reports/builds'
MODE='release'
CONTINUE_ON_ERROR=0
usage(){
  cat <<'HELP'
SYNOPSIS
  🏗️ Builds flutter_esptool example apps and writes a timestamped report.

USAGE
  ./scripts/macos/build.zsh [--report-dir DIR] [--mode release|debug|profile] [--continue-on-error] [--help]
HELP
}
while (( $# )); do
  case "$1" in
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --continue-on-error) CONTINUE_ON_ERROR=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "❌ Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done
case "$MODE" in release|debug|profile) ;; *) echo '❌ --mode must be release, debug, or profile' >&2; exit 2 ;; esac
if [[ -t 1 ]]; then C0=$'\033[0m'; CB=$'\033[36m'; CG=$'\033[32m'; CY=$'\033[33m'; CR=$'\033[31m'; CM=$'\033[35m'; else C0=''; CB=''; CG=''; CY=''; CR=''; CM=''; fi
step(){ printf '\n%s🔷 %s%s\n' "$CB" "$*" "$C0"; }; ok(){ printf '%s✅ %s%s\n' "$CG" "$*" "$C0"; }; warn(){ printf '%s⚠️  %s%s\n' "$CY" "$*" "$C0"; }; err(){ printf '%s❌ %s%s\n' "$CR" "$*" "$C0" >&2; }
ROOT="$(cd "${0:A:h}/../.." && pwd)"; STAMP="$(date +%Y%m%d-%H%M%S)"; RUN_DIR="$ROOT/$REPORT_DIR/$STAMP"; SUMMARY="$RUN_DIR/summary.md"; FAILURES=0
mkdir -p "$RUN_DIR"; printf '# 🏗️ Build report\n\nGenerated: %s\nMode: %s\n\n| Status | Step | Log |\n| --- | --- | --- |\n' "$(date -Iseconds)" "$MODE" > "$SUMMARY"
host(){ case "$(uname -s)" in Linux) echo Linux;; Darwin) echo Darwin;; MINGW*|MSYS*|CYGWIN*) echo Windows;; *) echo Unknown;; esac; }
run_logged(){ local name="$1" cwd="$2"; shift 2; local log="$RUN_DIR/${name//[^A-Za-z0-9_.-]/_}.log"; step "$name"; printf '   📁 %s\n   ▶ %s\n' "$cwd" "$*"; if (cd "$cwd" && "$@") >"$log" 2>&1; then ok "$name built"; printf '| ✅ | %s | [%s](%s) |\n' "$name" "$(basename "$log")" "$(basename "$log")" >> "$SUMMARY"; else err "$name failed"; printf '| ❌ | %s | [%s](%s) |\n' "$name" "$(basename "$log")" "$(basename "$log")" >> "$SUMMARY"; FAILURES=$((FAILURES+1)); (( CONTINUE_ON_ERROR )) || exit 1; fi; }
skip(){ warn "Skipping $1 on $(host) host"; printf '| ⚪ | %s | Skipped on %s host |\n' "$1" "$(host)" >> "$SUMMARY"; }
can_build(){ local target="$1" h="$(host)"; case "$target" in web|android-apk) return 0;; windows) [[ "$h" == Windows ]];; linux) [[ "$h" == Linux ]];; macos|ios-no-codesign) [[ "$h" == Darwin ]];; esac; }
run_target(){
  local name="$1" cwd="$2" target="$3"
  case "$target" in
    web) run_logged "$name" "$cwd" flutter build web --"$MODE" ;;
    windows) run_logged "$name" "$cwd" flutter build windows --"$MODE" ;;
    linux) run_logged "$name" "$cwd" flutter build linux --"$MODE" ;;
    macos) run_logged "$name" "$cwd" flutter build macos --"$MODE" ;;
    android-apk) run_logged "$name" "$cwd" flutter build apk --"$MODE" ;;
    ios-no-codesign) run_logged "$name" "$cwd" flutter build ios --no-codesign --"$MODE" ;;
  esac
}
printf '%s╔════════════════════════════════════════════════════════════╗%s\n' "$CM" "$C0"; printf '%s║ 🏗️ flutter_esptool build runner                           ║%s\n' "$CM" "$C0"; printf '%s╚════════════════════════════════════════════════════════════╝%s\n' "$CM" "$C0"; printf '%s📊 Report: %s%s\n' "$CB" "$RUN_DIR" "$C0"
for app in esptool_cli esptool_ui; do for target in web windows linux macos android-apk ios-no-codesign; do name="$app-$target-$MODE"; if can_build "$target"; then run_target "$name" "$ROOT/example/$app" "$target"; else skip "$name"; fi; done; done
printf '\nFailures: %s\n' "$FAILURES" >> "$SUMMARY"; if (( FAILURES == 0 )); then ok "Build run completed. Report: $RUN_DIR"; else err "$FAILURES build step(s) failed. Report: $RUN_DIR"; exit 1; fi

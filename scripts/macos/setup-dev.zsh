#!/usr/bin/env zsh
#
# SYNOPSIS
#   🚀 Idempotently prepares a macOS machine for flutter_esptool development.
#
# USAGE
#   ./scripts/macos/setup-dev.zsh [--yes] [--dry-run] [--no-elevate] [--help]
#
# DESCRIPTION
#   Installs or updates Git, Visual Studio Code, Android Studio, Flutter,
#   Java 17, Android command-line tools/platform tools, and Oh My Posh using
#   Homebrew. Configures zsh startup with the M365Princess Oh My Posh theme.

set -euo pipefail

YES=0
DRY_RUN=0
NO_ELEVATE=0

usage() {
  cat <<'HELP'
SYNOPSIS
  🚀 Idempotently prepares a macOS machine for flutter_esptool development.

USAGE
  ./scripts/macos/setup-dev.zsh [--yes] [--dry-run] [--no-elevate] [--help]

DESCRIPTION
  Installs or updates Git, Visual Studio Code, Android Studio, Flutter,
  Java 17, Android command-line tools/platform tools, and Oh My Posh using
  Homebrew. Configures zsh startup with the M365Princess Oh My Posh theme.
HELP
}
for arg in "$@"; do
  case "$arg" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --no-elevate) NO_ELEVATE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "❌ Unknown argument: $arg" >&2; usage; exit 2 ;;
  esac
done

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BLUE=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_MAGENTA=$'\033[35m'
else
  C_RESET=''; C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_MAGENTA=''
fi

step() { printf '\n%s🔷 %s%s\n' "$C_BLUE" "$*" "$C_RESET"; }
ok() { printf '%s✅ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '%s⚠️  %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
fail() { printf '%s❌ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }

run() {
  if (( DRY_RUN )); then warn "DRY-RUN: $*"; return 0; fi
  printf '   ▶ %s\n' "$*"
  "$@"
}

as_root() {
  if (( DRY_RUN )); then warn "DRY-RUN: sudo $*"; return 0; fi
  if (( EUID == 0 || NO_ELEVATE == 1 )); then "$@"; else sudo "$@"; fi
}

has() { command -v "$1" >/dev/null 2>&1; }

ensure_xcode_tools() {
  step 'Checking Xcode Command Line Tools'
  if xcode-select -p >/dev/null 2>&1; then ok 'Xcode Command Line Tools available'; return; fi
  if (( DRY_RUN )); then warn 'DRY-RUN: xcode-select --install'; return; fi
  xcode-select --install || true
  warn 'Finish the Xcode Command Line Tools installer, then re-run this script.'
}

ensure_homebrew() {
  step 'Checking Homebrew'
  if has brew; then ok 'Homebrew available'; run brew update; return; fi
  if (( DRY_RUN )); then warn 'DRY-RUN: install Homebrew'; return; fi
  NONINTERACTIVE=$YES /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi
  if [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
}

brew_install_or_upgrade() {
  local formula="$1"
  if brew list --formula "$formula" >/dev/null 2>&1; then run brew upgrade "$formula" || ok "$formula already current"; else run brew install "$formula"; fi
}

brew_cask_install_or_upgrade() {
  local cask="$1"
  if brew list --cask "$cask" >/dev/null 2>&1; then run brew upgrade --cask "$cask" || ok "$cask already current"; else run brew install --cask "$cask"; fi
}

configure_shell() {
  step 'Configuring zsh startup with Oh My Posh M365Princess'
  local file="$HOME/.zshrc"
  local start='# >>> flutter_esptool dev setup >>>'
  local end='# <<< flutter_esptool dev setup <<<'
  local block="$start
export PATH=\"/opt/homebrew/bin:/usr/local/bin:\$HOME/development/flutter/bin:\$PATH\"
export ANDROID_HOME=\"\$HOME/Library/Android/sdk\"
export ANDROID_SDK_ROOT=\"\$ANDROID_HOME\"
export PATH=\"\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH\"
if command -v oh-my-posh >/dev/null 2>&1; then
  eval \"\$(oh-my-posh init zsh --config \"\$(brew --prefix oh-my-posh)/themes/M365Princess.omp.json\")\"
fi
$end"
  if (( DRY_RUN )); then warn "DRY-RUN: update $file"; return; fi
  touch "$file"
  python3 - "$file" "$start" "$end" "$block" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1]); start=sys.argv[2]; end=sys.argv[3]; block=sys.argv[4]
text = path.read_text() if path.exists() else ''
pattern = re.escape(start) + r'.*?' + re.escape(end)
new = re.sub(pattern, block, text, flags=re.S) if re.search(pattern, text, flags=re.S) else text.rstrip() + '\n\n' + block + '\n'
path.write_text(new)
PY
  ok "Configured $file"
}

main() {
  printf '%s╔════════════════════════════════════════════════════════════╗%s\n' "$C_MAGENTA" "$C_RESET"
  printf '%s║ 🚀 flutter_esptool macOS development setup                ║%s\n' "$C_MAGENTA" "$C_RESET"
  printf '%s╚════════════════════════════════════════════════════════════╝%s\n' "$C_MAGENTA" "$C_RESET"
  (( YES )) && ok 'Non-interactive mode enabled where supported'

  ensure_xcode_tools
  ensure_homebrew

  step 'Installing command-line development tools'
  brew_install_or_upgrade git
  brew_install_or_upgrade flutter
  brew_install_or_upgrade openjdk@17
  brew_install_or_upgrade android-platform-tools
  brew_install_or_upgrade android-commandlinetools
  brew_install_or_upgrade oh-my-posh

  step 'Installing desktop development apps'
  brew_cask_install_or_upgrade visual-studio-code
  brew_cask_install_or_upgrade android-studio

  configure_shell

  step 'Accepting Android licenses and running Flutter doctor when available'
  export PATH="$(brew --prefix flutter 2>/dev/null)/bin:$HOME/development/flutter/bin:$PATH"
  export ANDROID_HOME="$HOME/Library/Android/sdk"
  export ANDROID_SDK_ROOT="$ANDROID_HOME"
  export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
  if has flutter; then
    yes | flutter doctor --android-licenses >/dev/null 2>&1 || warn 'Android licenses not accepted yet; open Android Studio, install SDKs, then run flutter doctor --android-licenses.'
    run flutter doctor
  else
    warn 'Flutter command not found. Restart zsh and run flutter doctor.'
  fi

  ok 'macOS development setup completed. Restart shells to load PATH/profile changes.'
}

main

#!/usr/bin/env bash
# shellcheck shell=bash
#
# SYNOPSIS
#   🚀 Idempotently prepares a Linux machine for flutter_esptool development.
#
# USAGE
#   ./scripts/linux/setup-dev.sh [--yes] [--dry-run] [--no-elevate] [--help]
#
# DESCRIPTION
#   Installs or updates Git, VS Code, Android Studio, Flutter, Java 17,
#   Android SDK tools where available, and Oh My Posh. Supports common distro
#   package managers: apt, dnf, yum, pacman, zypper, apk, plus snap/flatpak
#   fallbacks for desktop applications. Safe to run multiple times.

set -Eeuo pipefail

YES=0
DRY_RUN=0
NO_ELEVATE=0
SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<'HELP'
SYNOPSIS
  🚀 Idempotently prepares a Linux machine for flutter_esptool development.

USAGE
  ./scripts/linux/setup-dev.sh [--yes] [--dry-run] [--no-elevate] [--help]

DESCRIPTION
  Installs or updates Git, VS Code, Android Studio, Flutter, Java 17,
  Android SDK tools where available, and Oh My Posh. Supports common distro
  package managers: apt, dnf, yum, pacman, zypper, apk, plus snap/flatpak
  fallbacks for desktop applications. Safe to run multiple times.
HELP
}

for arg in "$@"; do
  case "$arg" in
  --yes | -y) YES=1 ;;
  --dry-run) DRY_RUN=1 ;;
  --no-elevate) NO_ELEVATE=1 ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "❌ Unknown argument: $arg" >&2
    usage
    exit 2
    ;;
  esac
done

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BLUE=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_MAGENTA=$'\033[35m'
else
  C_RESET=''
  C_BLUE=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
  C_MAGENTA=''
fi

step() { printf '\n%s🔷 %s%s\n' "$C_BLUE" "$*" "$C_RESET"; }
ok() { printf '%s✅ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '%s⚠️  %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
fail() { printf '%s❌ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }

run() {
  if ((DRY_RUN)); then
    warn "DRY-RUN: $*"
    return 0
  fi
  printf '   ▶ %s\n' "$*"
  "$@"
}

need_sudo() {
  if ((EUID == 0)); then return 1; fi
  if ((NO_ELEVATE)); then return 1; fi
  return 0
}

as_root() {
  if ((DRY_RUN)); then
    warn "DRY-RUN: sudo $*"
    return 0
  fi
  if ((EUID == 0)); then "$@"; elif ((NO_ELEVATE)); then "$@"; else sudo "$@"; fi
}

has() { command -v "$1" >/dev/null 2>&1; }

pkg_manager() {
  for pm in apt-get dnf yum pacman zypper apk; do
    if has "$pm"; then
      echo "$pm"
      return 0
    fi
  done
  return 1
}

install_packages() {
  local pm="$1"
  shift
  case "$pm" in
  apt-get)
    as_root apt-get update
    as_root apt-get install -y "$@"
    ;;
  dnf) as_root dnf install -y "$@" ;;
  yum) as_root yum install -y "$@" ;;
  pacman) as_root pacman -Sy --needed --noconfirm "$@" ;;
  zypper) as_root zypper --non-interactive install --no-recommends "$@" ;;
  apk) as_root apk add --no-cache "$@" ;;
  esac
}

install_core_packages() {
  local pm="$1"
  step "Installing core packages with $pm"
  case "$pm" in
  apt-get) install_packages "$pm" git curl unzip xz-utils zip file tar ca-certificates python3 clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev openjdk-17-jdk ;;
  dnf | yum) install_packages "$pm" git curl unzip xz zip file tar ca-certificates python3 clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel java-17-openjdk-devel ;;
  pacman) install_packages "$pm" git curl unzip xz zip file tar python3 clang cmake ninja pkgconf gtk3 jdk17-openjdk ;;
  zypper) install_packages "$pm" git curl unzip xz zip file tar ca-certificates python3 clang cmake ninja pkg-config gtk3-devel xz-devel java-17-openjdk-devel ;;
  apk) install_packages "$pm" git curl unzip xz zip file tar ca-certificates python3 clang cmake ninja pkgconf gtk+3.0-dev openjdk17 ;;
  esac
}

install_snap_or_flatpak_app() {
  local snap_name="$1" flatpak_id="$2" human="$3" snap_flags="${4:-}"
  if has snap; then
    if snap list "$snap_name" >/dev/null 2>&1; then
      ok "$human already installed via snap"
    else
      # shellcheck disable=SC2086
      as_root snap install "$snap_name" $snap_flags
    fi
  elif has flatpak; then
    if flatpak info "$flatpak_id" >/dev/null 2>&1; then
      ok "$human already installed via flatpak"
    else
      run flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
      run flatpak install -y flathub "$flatpak_id"
    fi
  else
    warn "Install $human manually, or install snap/flatpak and re-run $SCRIPT_NAME"
  fi
}

install_flutter() {
  step 'Installing or updating Flutter'
  if has flutter; then
    run flutter upgrade
    return
  fi
  local target="$HOME/development/flutter"
  if [[ -d "$target/.git" ]]; then
    run git -C "$target" pull --ff-only
  else
    run mkdir -p "$(dirname "$target")"
    run git clone https://github.com/flutter/flutter.git -b stable "$target"
  fi
  add_shell_block "$HOME/.bashrc" "export PATH=\"\$HOME/development/flutter/bin:\$PATH\""
  [[ -f "$HOME/.zshrc" ]] && add_shell_block "$HOME/.zshrc" "export PATH=\"\$HOME/development/flutter/bin:\$PATH\""
  export PATH="$target/bin:$PATH"
}

install_oh_my_posh() {
  step 'Installing or updating Oh My Posh'
  if has oh-my-posh; then
    run oh-my-posh upgrade || warn 'Oh My Posh self-upgrade skipped; continuing.'
  else
    if ((DRY_RUN)); then
      warn 'DRY-RUN: curl -s https://ohmyposh.dev/install.sh | bash -s'
      return
    fi
    curl -s https://ohmyposh.dev/install.sh | bash -s
  fi
}

add_shell_block() {
  local file="$1" extra_path_line="${2:-}"
  local start='# >>> flutter_esptool dev setup >>>'
  local end='# <<< flutter_esptool dev setup <<<'
  local block
  block="$start
$extra_path_line
if command -v oh-my-posh >/dev/null 2>&1; then
  theme=\"\${POSH_THEMES_PATH:-\$HOME/.cache/oh-my-posh/themes}/M365Princess.omp.json\"
  [ -f \"\$theme\" ] || theme=\"/usr/local/share/oh-my-posh/themes/M365Princess.omp.json\"
  eval \"\$(oh-my-posh init bash --config \"\$theme\")\"
fi
$end"
  if ((DRY_RUN)); then
    warn "DRY-RUN: update $file"
    return
  fi
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

configure_shells() {
  step 'Configuring shell startup with Oh My Posh M365Princess'
  add_shell_block "$HOME/.bashrc" ''
  if [[ -f "$HOME/.zshrc" ]]; then
    local start='# >>> flutter_esptool dev setup >>>'
    local end='# <<< flutter_esptool dev setup <<<'
    local block="$start
if command -v oh-my-posh >/dev/null 2>&1; then
  theme=\"\${POSH_THEMES_PATH:-\$HOME/.cache/oh-my-posh/themes}/M365Princess.omp.json\"
  [ -f \"\$theme\" ] || theme=\"/usr/local/share/oh-my-posh/themes/M365Princess.omp.json\"
  eval \"\$(oh-my-posh init zsh --config \"\$theme\")\"
fi
$end"
    if ((DRY_RUN)); then warn "DRY-RUN: update $HOME/.zshrc"; else
      python3 - "$HOME/.zshrc" "$start" "$end" "$block" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1]); start=sys.argv[2]; end=sys.argv[3]; block=sys.argv[4]
text = path.read_text() if path.exists() else ''
pattern = re.escape(start) + r'.*?' + re.escape(end)
new = re.sub(pattern, block, text, flags=re.S) if re.search(pattern, text, flags=re.S) else text.rstrip() + '\n\n' + block + '\n'
path.write_text(new)
PY
      ok "Configured $HOME/.zshrc"
    fi
  fi
}

main() {
  printf '%s╔════════════════════════════════════════════════════════════╗%s\n' "$C_MAGENTA" "$C_RESET"
  printf '%s║ 🚀 flutter_esptool Linux development setup                ║%s\n' "$C_MAGENTA" "$C_RESET"
  printf '%s╚════════════════════════════════════════════════════════════╝%s\n' "$C_MAGENTA" "$C_RESET"
  ((YES)) && ok 'Non-interactive mode enabled where supported'

  local pm
  pm="$(pkg_manager)" || {
    fail 'No supported package manager found.'
    exit 1
  }
  install_core_packages "$pm"

  step 'Installing desktop development apps'
  install_snap_or_flatpak_app code com.visualstudio.code 'Visual Studio Code' '--classic'
  install_snap_or_flatpak_app android-studio com.google.AndroidStudio 'Android Studio' '--classic'

  install_flutter
  install_oh_my_posh
  configure_shells

  step 'Accepting Android licenses and running Flutter doctor when available'
  if has flutter; then
    yes | flutter doctor --android-licenses >/dev/null 2>&1 || warn 'Android licenses not accepted yet; open Android Studio, install SDKs, then run flutter doctor --android-licenses.'
    run flutter doctor
  else
    warn 'Flutter command not found. Restart the shell and run flutter doctor.'
  fi

  ok 'Linux development setup completed. Restart shells to load PATH/profile changes.'
}

main

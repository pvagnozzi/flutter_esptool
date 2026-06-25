#!/bin/sh
# install-hooks.sh — Installs git hooks from scripts/hooks/ into .git/hooks/
# Make this script executable first: chmod +x scripts/install-hooks.sh

set -e

HOOKS_SOURCE_DIR="$(cd "$(dirname "$0")/hooks" && pwd)"
GIT_HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)/.git/hooks"

# Check that .git/hooks/ exists
if [ ! -d "$GIT_HOOKS_DIR" ]; then
  echo "❌ Directory not found: $GIT_HOOKS_DIR"
  echo "   Are you running this from the repository root?"
  exit 1
fi

echo "📂 Installing hooks from: $HOOKS_SOURCE_DIR"
echo "📂 Installing hooks into: $GIT_HOOKS_DIR"
echo ""

installed=0
for hook in "$HOOKS_SOURCE_DIR"/*; do
  hook_name="$(basename "$hook")"
  dest="$GIT_HOOKS_DIR/$hook_name"
  cp "$hook" "$dest"
  chmod +x "$dest"
  echo "✅ Installed: $hook_name"
  installed=$((installed + 1))
done

echo ""
echo "🎉 Done. $installed hook(s) installed successfully."

#!/bin/sh
# uninstall-hooks.sh — Removes git hooks installed from scripts/hooks/
# Make this script executable first: chmod +x scripts/uninstall-hooks.sh

set -e

HOOKS_SOURCE_DIR="$(cd "$(dirname "$0")/hooks" && pwd)"
GIT_HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)/.git/hooks"

# Check that .git/hooks/ exists
if [ ! -d "$GIT_HOOKS_DIR" ]; then
  echo "❌ Directory not found: $GIT_HOOKS_DIR"
  echo "   Are you running this from the repository root?"
  exit 1
fi

echo "🗑️  Removing hooks from: $GIT_HOOKS_DIR"
echo ""

removed=0
for hook in "$HOOKS_SOURCE_DIR"/*; do
  hook_name="$(basename "$hook")"
  dest="$GIT_HOOKS_DIR/$hook_name"
  if [ -f "$dest" ]; then
    rm "$dest"
    echo "🗑️  Removed: $hook_name"
    removed=$((removed + 1))
  else
    echo "⚠️  Not found (skipped): $hook_name"
  fi
done

echo ""
echo "🎉 Done. $removed hook(s) removed."

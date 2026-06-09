#!/bin/bash
# uninstall.sh — Remove Chinese Router hook config from ~/.claude/settings.json
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "No $SETTINGS_FILE found. Nothing to uninstall."
    exit 0
fi

# Check if our hooks exist
if ! jq -e '.hooks' "$SETTINGS_FILE" > /dev/null 2>&1; then
    echo "No hooks section found. Nothing to uninstall."
    exit 0
fi

# Remove UserPromptSubmit and Stop hooks added by chinese-router
tmp=$(mktemp)
jq 'del(.hooks.UserPromptSubmit) | del(.hooks.Stop)' "$SETTINGS_FILE" > "$tmp"

# If hooks object is now empty, remove it entirely
if jq -e '.hooks == {}' "$tmp" > /dev/null 2>&1; then
    jq 'del(.hooks)' "$tmp" > "$tmp.2"
    mv "$tmp.2" "$tmp"
fi

mv "$tmp" "$SETTINGS_FILE"
echo "Chinese Router Plugin hooks removed from $SETTINGS_FILE"
echo ""
echo "To also delete the plugin files, run:"
echo "  rm -rf $(dirname "$(dirname "${BASH_SOURCE[0]}")")"

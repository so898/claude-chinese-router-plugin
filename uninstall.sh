#!/bin/bash
# uninstall.sh — Remove Chinese Router hook config from ~/.claude/settings.json
set -euo pipefail

SETTINGS_FILE="$HOME/.claude/settings.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CN2EN_SCRIPT="$SCRIPT_DIR/scripts/cn2en.sh"
EN2CN_SCRIPT="$SCRIPT_DIR/scripts/en2cn.sh"
CN2EN_COMMAND="bash \"$CN2EN_SCRIPT\""
EN2CN_COMMAND="bash \"$EN2CN_SCRIPT\""
CN2EN_COMMAND_LEGACY="bash $CN2EN_SCRIPT"
EN2CN_COMMAND_LEGACY="bash $EN2CN_SCRIPT"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "No $SETTINGS_FILE found. Nothing to uninstall."
    exit 0
fi

# Check if our hooks exist
if ! jq -e '.hooks' "$SETTINGS_FILE" > /dev/null 2>&1; then
    echo "No hooks section found. Nothing to uninstall."
    exit 0
fi

# Remove only UserPromptSubmit and Stop hooks added by Chinese Router.
tmp=$(mktemp)
jq \
  --arg cn "$CN2EN_COMMAND" \
  --arg cn_legacy "$CN2EN_COMMAND_LEGACY" \
  --arg en "$EN2CN_COMMAND" \
  --arg en_legacy "$EN2CN_COMMAND_LEGACY" '
    def remove_commands($a; $b):
      map(.hooks = ((.hooks // []) | map(select(.command != $a and .command != $b)))) |
      map(select((.hooks // []) | length > 0));

    .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | remove_commands($cn; $cn_legacy)) |
    .hooks.Stop = ((.hooks.Stop // []) | remove_commands($en; $en_legacy)) |
    if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end |
    if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end
  ' "$SETTINGS_FILE" > "$tmp"

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

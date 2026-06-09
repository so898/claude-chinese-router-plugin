#!/bin/bash
# install.sh — Inject Chinese Router hook config into ~/.claude/settings.json
# Works around anthropics/claude-code#10225 (plugin UserPromptSubmit hooks don't fire)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
CN2EN_SCRIPT="$SCRIPT_DIR/scripts/cn2en.sh"
EN2CN_SCRIPT="$SCRIPT_DIR/scripts/en2cn.sh"
CN2EN_COMMAND="bash \"$CN2EN_SCRIPT\""
EN2CN_COMMAND="bash \"$EN2CN_SCRIPT\""
CN2EN_COMMAND_LEGACY="bash $CN2EN_SCRIPT"
EN2CN_COMMAND_LEGACY="bash $EN2CN_SCRIPT"

# Ensure ~/.claude directory exists
mkdir -p "$HOME/.claude"

# Hook configuration for this plugin (as jq-compatible JSON fragment)
NEW_HOOKS=$(jq -n --arg cn "$CN2EN_COMMAND" --arg en "$EN2CN_COMMAND" '{
  UserPromptSubmit: [
    {
      hooks: [
        {
          type: "command",
          command: $cn
        }
      ]
    }
  ],
  Stop: [
    {
      hooks: [
        {
          type: "command",
          command: $en
        }
      ]
    }
  ]
}')

if [ -f "$SETTINGS_FILE" ]; then
    # Merge: replace any existing Chinese Router hooks, preserve all other settings
    tmp=$(mktemp)
    jq \
      --argjson new "$NEW_HOOKS" \
      --arg cn "$CN2EN_COMMAND" \
      --arg cn_legacy "$CN2EN_COMMAND_LEGACY" \
      --arg en "$EN2CN_COMMAND" \
      --arg en_legacy "$EN2CN_COMMAND_LEGACY" '
        def remove_commands($a; $b):
          map(.hooks = ((.hooks // []) | map(select(.command != $a and .command != $b)))) |
          map(select((.hooks // []) | length > 0));

        .hooks.UserPromptSubmit = (((.hooks.UserPromptSubmit // []) | remove_commands($cn; $cn_legacy)) + $new.UserPromptSubmit) |
        .hooks.Stop = (((.hooks.Stop // []) | remove_commands($en; $en_legacy)) + $new.Stop)
    ' "$SETTINGS_FILE" > "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
    echo "Updated $SETTINGS_FILE"
else
    # Fresh install
    cat > "$SETTINGS_FILE" <<JSON
{
  "hooks": $NEW_HOOKS
}
JSON
    echo "Created $SETTINGS_FILE"
fi

echo ""
echo "Chinese Router Plugin hooks installed."
echo "  CN→EN: UserPromptSubmit → $CN2EN_SCRIPT"
echo "  EN→CN: Stop → $EN2CN_SCRIPT"
echo ""
echo "To uninstall, run: bash $SCRIPT_DIR/uninstall.sh"

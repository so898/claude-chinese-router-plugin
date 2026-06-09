#!/bin/bash
# install.sh — Inject Chinese Router hook config into ~/.claude/settings.json
# Works around anthropics/claude-code#10225 (plugin UserPromptSubmit hooks don't fire)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_FILE="$HOME/.claude/settings.json"
CN2EN_SCRIPT="$SCRIPT_DIR/scripts/cn2en.sh"
EN2CN_SCRIPT="$SCRIPT_DIR/scripts/en2cn.sh"

# Ensure ~/.claude directory exists
mkdir -p "$HOME/.claude"

# Hook configuration for this plugin (as jq-compatible JSON fragment)
NEW_HOOKS=$(cat <<JSON
{
  "UserPromptSubmit": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash $CN2EN_SCRIPT"
        }
      ]
    }
  ],
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "bash $EN2CN_SCRIPT"
        }
      ]
    }
  ]
}
JSON
)

if [ -f "$SETTINGS_FILE" ]; then
    # Merge: append our hooks to existing hooks, preserve all other settings
    tmp=$(mktemp)
    jq --argjson new "$NEW_HOOKS" '
        .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + $new.UserPromptSubmit) |
        .hooks.Stop = ((.hooks.Stop // []) + $new.Stop)
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

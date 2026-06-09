#!/bin/bash
# install.sh — Inject Chinese Router hook config into .claude/settings.local.json
# Works around anthropics/claude-code#10225 (plugin UserPromptSubmit hooks don't fire)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS_DIR=".claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.local.json"
CN2EN_SCRIPT="$SCRIPT_DIR/scripts/cn2en.sh"
EN2CN_SCRIPT="$SCRIPT_DIR/scripts/en2cn.sh"

# Ensure .claude directory exists
mkdir -p "$SETTINGS_DIR"

# Hook configuration to inject
HOOK_CONFIG=$(cat <<JSON
{
  "hooks": {
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
}
JSON
)

if [ -f "$SETTINGS_FILE" ]; then
    # Merge: keep existing settings, update hooks
    tmp=$(mktemp)
    jq --argjson hooks "$(echo "$HOOK_CONFIG" | jq '.hooks')" '.hooks = $hooks' "$SETTINGS_FILE" > "$tmp" 2>/dev/null || cp "$SETTINGS_FILE" "$tmp"
    mv "$tmp" "$SETTINGS_FILE"
    echo "Updated existing $SETTINGS_FILE"
else
    echo "$HOOK_CONFIG" > "$SETTINGS_FILE"
    echo "Created $SETTINGS_FILE"
fi

echo ""
echo "Chinese Router Plugin hooks installed."
echo "  CN→EN: UserPromptSubmit → $CN2EN_SCRIPT"
echo "  EN→CN: Stop → $EN2CN_SCRIPT"
echo ""
echo "To uninstall, remove the hooks section from $SETTINGS_FILE"

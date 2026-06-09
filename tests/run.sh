#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export PATH="$TMP_DIR/bin:$PATH"
mkdir -p "$TMP_DIR/bin"

cat > "$TMP_DIR/bin/claude" <<'SH'
#!/bin/bash
set -euo pipefail
prompt="${*: -1}"
if [[ "$prompt" == *"Translate the following Chinese text"* ]]; then
  printf 'Create a utils.py file in src.'
elif [[ "$prompt" == *"Translate the following English text"* ]]; then
  printf '我已经完成任务。'
else
  printf 'stub-claude-output'
fi
SH
chmod +x "$TMP_DIR/bin/claude"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_json_filter() {
  local input="$1"
  local filter="$2"
  local expected="$3"
  local actual
  actual="$(printf '%s' "$input" | jq -r "$filter")"
  [ "$actual" = "$expected" ] || fail "expected jq $filter to be '$expected', got '$actual'"
}

bash -n "$ROOT_DIR/scripts/cn2en.sh"
bash -n "$ROOT_DIR/scripts/en2cn.sh"
bash -n "$ROOT_DIR/install.sh"
bash -n "$ROOT_DIR/uninstall.sh"
pass "shell scripts parse"

cn_output="$(printf '{"prompt":"帮我在 src 目录下创建 utils.py"}' | bash "$ROOT_DIR/scripts/cn2en.sh")"
assert_json_filter "$cn_output" '.hookSpecificOutput.hookEventName' 'UserPromptSubmit'
assert_json_filter "$cn_output" '.hookSpecificOutput.additionalContext | contains("Create a utils.py file in src.")' 'true'
pass "Chinese prompt returns UserPromptSubmit additionalContext"

en_output="$(printf '{"prompt":"Create a utils.py file in src."}' | bash "$ROOT_DIR/scripts/cn2en.sh")"
assert_json_filter "$en_output" 'type' 'object'
assert_json_filter "$en_output" 'length' '0'
pass "English prompt passes without extra context"

stop_output="$(printf '{"last_assistant_message":"I have completed the requested task and updated the files.","transcript_path":null}' | bash "$ROOT_DIR/scripts/en2cn.sh")"
assert_json_filter "$stop_output" '.systemMessage | startswith("🇨🇳 ")' 'true'
assert_json_filter "$stop_output" '.systemMessage | contains("我已经完成任务。")' 'true'
pass "Stop hook translates last_assistant_message without transcript"

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.claude"
cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": ["Bash(git status)"]
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo existing-user-prompt-hook"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo existing-stop-hook"
          }
        ]
      }
    ]
  }
}
JSON

bash "$ROOT_DIR/install.sh" >/dev/null
bash "$ROOT_DIR/install.sh" >/dev/null

settings="$HOME/.claude/settings.json"
assert_json_filter "$(cat "$settings")" '.permissions.allow[0]' 'Bash(git status)'
assert_json_filter "$(cat "$settings")" '[.hooks.UserPromptSubmit[].hooks[].command | select(contains("scripts/cn2en.sh"))] | length' '1'
assert_json_filter "$(cat "$settings")" '[.hooks.Stop[].hooks[].command | select(contains("scripts/en2cn.sh"))] | length' '1'
assert_json_filter "$(cat "$settings")" '[.hooks.UserPromptSubmit[].hooks[].command | select(. == "echo existing-user-prompt-hook")] | length' '1'
assert_json_filter "$(cat "$settings")" '[.hooks.Stop[].hooks[].command | select(. == "echo existing-stop-hook")] | length' '1'
pass "install is idempotent and preserves existing settings"

bash "$ROOT_DIR/uninstall.sh" >/dev/null

assert_json_filter "$(cat "$settings")" '[.hooks.UserPromptSubmit[].hooks[].command | select(contains("scripts/cn2en.sh"))] | length' '0'
assert_json_filter "$(cat "$settings")" '[.hooks.Stop[].hooks[].command | select(contains("scripts/en2cn.sh"))] | length' '0'
assert_json_filter "$(cat "$settings")" '[.hooks.UserPromptSubmit[].hooks[].command | select(. == "echo existing-user-prompt-hook")] | length' '1'
assert_json_filter "$(cat "$settings")" '[.hooks.Stop[].hooks[].command | select(. == "echo existing-stop-hook")] | length' '1'
pass "uninstall removes only Chinese Router hooks"

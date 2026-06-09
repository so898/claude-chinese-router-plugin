# Chinese Router Plugin Implementation Plan

> **Status:** Historical implementation plan. The current Claude Code hook mechanism does not allow `UserPromptSubmit` to replace the user's prompt. The implemented project now injects an English translation through `hookSpecificOutput.additionalContext`, uses `systemMessage` for the Chinese output translation, and writes hooks to `~/.claude/settings.json` through idempotent install/uninstall scripts. Use `README.md`, the current scripts, and `docs/superpowers/specs/2026-06-09-chinese-router-plugin-design.md` as the source of truth.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code translation helper that detects Chinese user input, injects an English translation as priority context, then translates Claude's English output back to Chinese for the user — via UserPromptSubmit and Stop hooks.

**Architecture:** Two shell scripts act as hook handlers. `cn2en.sh` parses UserPromptSubmit stdin JSON, detects Chinese, spawns a guarded `claude --print` call to translate CN→EN, and emits JSON `additionalContext`. `en2cn.sh` parses Stop stdin JSON, prefers `last_assistant_message`, translates EN→CN via guarded `claude --print`, and emits JSON `systemMessage`. Hook configuration lives in global `~/.claude/settings.json` due to known bug #10225.

**Tech Stack:** Bash, jq, grep, Claude Code CLI, Claude Code Hooks API

---

### Task 1: Plugin Metadata

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.gitignore`

- [ ] **Step 1: Create plugin.json**

```json
{
  "name": "chinese-router",
  "description": "Chinese-English translation proxy via Claude Code hooks. Prevents Chinese text from reaching the main Claude session to avoid degraded performance on Chinese-language tasks.",
  "version": "1.0.0",
  "author": { "name": "Bill Cheng" },
  "license": "MIT"
}
```

- [ ] **Step 2: Create .gitignore**

```
.claude/settings.local.json
```

- [ ] **Step 3: Verify files exist**

Run: `ls -la .claude-plugin/plugin.json .gitignore`
Expected: both files exist

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .gitignore
git commit -m "feat: add plugin metadata and gitignore"
```

---

### Task 2: SKILL.md

**Files:**
- Create: `skills/chinese-router/SKILL.md`

- [ ] **Step 1: Create SKILL.md**

```markdown
---
name: chinese-router
description: Use when the Chinese Router translation proxy is active. This skill makes Claude aware that user prompts have been automatically translated from Chinese to English, and that responses will be translated back to Chinese for the user.
---

# Chinese Router Translation Proxy

## What's Happening

A translation proxy is routing all messages through CN-EN-CN translation:

1. User writes in Chinese
2. Proxy translates to English before Claude sees it
3. Claude processes in English only
4. Proxy translates Claude's English output back to Chinese

## What This Means for You

- All prompts you receive are English translations of the user's original Chinese input
- You should respond in natural English — the proxy handles Chinese output
- Preserve code blocks, technical terms, and formatting exactly as-is
- The user sees both your English output and a Chinese translation appended at the end
- Translation adds ~1-3 seconds per interaction

## When the User Asks About the Plugin

Explain that the Chinese Router Plugin translates between Chinese and English automatically to optimize processing quality. The translation layer is transparent to normal use.
```

- [ ] **Step 2: Verify file**

Run: `head -5 skills/chinese-router/SKILL.md`
Expected: YAML frontmatter with `name: chinese-router`

- [ ] **Step 3: Commit**

```bash
git add skills/chinese-router/SKILL.md
git commit -m "feat: add chinese-router skill definition"
```

---

### Task 3: CN-to-EN Translation Script (cn2en.sh)

**Files:**
- Create: `scripts/cn2en.sh`

This is the core UserPromptSubmit hook handler. It receives the user's prompt via stdin JSON, detects Chinese characters, and translates to English before Claude processes it.

- [ ] **Step 1: Write cn2en.sh**

```bash
#!/bin/bash
# cn2en.sh — UserPromptSubmit hook handler
# Reads stdin JSON, detects Chinese in prompt, translates CN→EN via Claude subprocess.
# Stdout replaces the user's original prompt for the main Claude session.
set -euo pipefail

# Read hook input from stdin
input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt')

# If prompt is empty or null, pass through
if [ -z "$prompt" ] || [ "$prompt" = "null" ]; then
    echo "$prompt"
    exit 0
fi

# Detect Chinese characters (CJK Unified Ideographs: U+4E00 to U+9FFF)
if echo "$prompt" | grep -qP '[\x{4e00}-\x{9fff}]'; then
    # Build translation prompt and send to Claude subprocess
    # CLAUDECODE= bypasses the nested-session guard
    translation_prompt=$(printf 'Translate the following Chinese text to natural, fluent English.\nOutput ONLY the English translation without any explanation, quotes, or formatting.\n\n---\n%s' "$prompt")
    translated=$(CLAUDECODE= claude --print "$translation_prompt" 2>/dev/null)

    if [ -n "$translated" ]; then
        echo "$translated"
    else
        # Fallback: if translation failed, pass original (Claude may still handle it)
        echo "$prompt"
    fi
else
    # No Chinese detected — pass through unchanged
    echo "$prompt"
fi
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/cn2en.sh`

- [ ] **Step 3: Test — Chinese input gets translated**

Run: `echo '{"prompt": "帮我在 src 目录下创建一个 utils.py 文件"}' | bash scripts/cn2en.sh`
Expected: stdout contains English translation (e.g., "Create a utils.py file in the src directory"), not Chinese

- [ ] **Step 4: Test — English input passes through**

Run: `echo '{"prompt": "Create a utils.py file in src/"}' | bash scripts/cn2en.sh`
Expected: stdout is exactly "Create a utils.py file in src/"

- [ ] **Step 5: Test — empty prompt passes through**

Run: `echo '{"prompt": ""}' | bash scripts/cn2en.sh`
Expected: stdout is empty, exit code 0

- [ ] **Step 6: Commit**

```bash
git add scripts/cn2en.sh
git commit -m "feat: add cn2en.sh — UserPromptSubmit hook handler for CN→EN translation"
```

---

### Task 4: EN-to-CN Translation Script (en2cn.sh)

**Files:**
- Create: `scripts/en2cn.sh`

This is the Stop hook handler. It parses the transcript JSONL file to extract Claude's last assistant message, translates it to Chinese, and outputs the translation to stdout (which appears in the terminal transcript).

- [ ] **Step 1: Write en2cn.sh**

```bash
#!/bin/bash
# en2cn.sh — Stop hook handler
# Reads stdin JSON, parses transcript JSONL for last assistant message,
# translates EN→CN via Claude subprocess, appends translation to output.
set -euo pipefail

# Read hook input from stdin
input=$(cat)
transcript_path=$(echo "$input" | jq -r '.transcript_path')

# Validate transcript path
if [ -z "$transcript_path" ] || [ "$transcript_path" = "null" ] || [ ! -f "$transcript_path" ]; then
    exit 0
fi

# Extract last assistant text message from transcript JSONL
# assistant messages: {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "..."}, ...]}}
# We tail the last 100 lines and extract all text blocks from assistant messages, taking the final one
last_msg=$(tail -100 "$transcript_path" 2>/dev/null | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | tail -1)

# Skip if no assistant message found or message is too short
if [ -z "$last_msg" ] || [ ${#last_msg} -lt 10 ]; then
    exit 0
fi

# Translate EN→CN via Claude subprocess
translation_prompt=$(printf 'Translate the following English text to natural, fluent Chinese.\nOutput ONLY the Chinese translation without any explanation, quotes, or formatting.\n\n---\n%s' "$last_msg")
translated=$(CLAUDECODE= claude --print "$translation_prompt" 2>/dev/null)

if [ -n "$translated" ]; then
    printf '\n────────────────────\n%s\n' "$translated"
fi
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/en2cn.sh`

- [ ] **Step 3: Test — parses transcript correctly**

First, create a mock transcript to test against:

Run:
```bash
cat > /tmp/mock_transcript.jsonl << 'JSONL'
{"type": "user", "message": {"role": "user", "content": "Create a utils.py file"}}
{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "I've created the utils.py file for you. It contains common utility functions."}]}}
JSONL
```

Then test:
```bash
echo '{"transcript_path": "/tmp/mock_transcript.jsonl"}' | bash scripts/en2cn.sh
```

Expected: stdout contains `────────────────────` separator followed by Chinese translation

- [ ] **Step 4: Test — missing transcript exits cleanly**

Run: `echo '{"transcript_path": "/nonexistent/path.jsonl"}' | bash scripts/en2cn.sh`
Expected: exit code 0, no output (or minimal)

- [ ] **Step 5: Cleanup test file**

Run: `rm -f /tmp/mock_transcript.jsonl`

- [ ] **Step 6: Commit**

```bash
git add scripts/en2cn.sh
git commit -m "feat: add en2cn.sh — Stop hook handler for EN→CN translation"
```

---

### Task 5: Install Script (install.sh)

**Files:**
- Create: `install.sh`

Automates hook configuration injection into project-level `settings.local.json`. This works around bug #10225 where UserPromptSubmit hooks from plugin configs don't execute.

- [ ] **Step 1: Write install.sh**

```bash
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
```

- [ ] **Step 2: Make executable**

Run: `chmod +x install.sh`

- [ ] **Step 3: Test — fresh install creates settings.local.json**

Run:
```bash
rm -f .claude/settings.local.json
bash install.sh
cat .claude/settings.local.json | jq '.hooks.UserPromptSubmit[0].hooks[0].command'
```

Expected: jq outputs the path to cn2en.sh

- [ ] **Step 4: Test — re-run preserves custom settings**

Run:
```bash
echo '{"customField": true}' | jq '.' > .claude/settings.local.json
bash install.sh
cat .claude/settings.local.json | jq '.customField'
```

Expected: jq outputs `true` (custom field preserved while hooks are updated)

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh — inject hook config into settings.local.json"
```

---

### Task 6: End-to-End Verification

**Files:**
- (none — manual verification using Claude Code session)

This task verifies the complete flow works in a real Claude Code session.

- [ ] **Step 1: Verify all files are in place**

Run: `find . -type f | sort`
Expected:
```
.claude-plugin/plugin.json
.gitignore
install.sh
scripts/cn2en.sh
scripts/en2cn.sh
skills/chinese-router/SKILL.md
```

- [ ] **Step 2: Run install.sh**

Run: `bash install.sh`
Expected: "Created .claude/settings.local.json" or "Updated existing..."

- [ ] **Step 3: Verify settings.local.json hook commands exist**

Run: `cat .claude/settings.local.json | jq '.hooks | keys'`
Expected: `["UserPromptSubmit", "Stop"]`

- [ ] **Step 4: Verify cn2en.sh is executable from hook path**

Run: `bash "$(cat .claude/settings.local.json | jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' | sed 's/bash //')" --help 2>&1 || true`
Expected: script runs (may output nothing since no stdin, but should not error with "No such file")

- [ ] **Step 5: Manual integration test**

Open a Claude Code session and submit a Chinese prompt, e.g.: "帮我查看当前目录下有什么文件"

Expected behavior:
1. UserPromptSubmit hook fires, cn2en.sh translates to English
2. Claude processes in English, runs `ls` or similar
3. Claude's English output displays
4. Stop hook fires, en2cn.sh appends Chinese translation after `────` separator

- [ ] **Step 6: Test with English-only input (passthrough)**

Submit: "List all files in the current directory"

Expected: No translation overhead, prompt passes through unchanged, no Chinese translation appended

- [ ] **Step 7: Final commit (if any settings.local.json changes were made for testing)**

```bash
git status
```

If settings.local.json is untracked, confirm it's gitignored and leave it alone.

---

### File Structure (after all tasks)

```
claude-chinese-router-plugin/
├── .claude-plugin/
│   └── plugin.json
├── .gitignore
├── .claude/
│   └── settings.local.json      # Generated by install.sh, gitignored
├── docs/
│   └── superpowers/
│       ├── specs/
│       │   └── 2026-06-09-chinese-router-plugin-design.md
│       └── plans/
│           └── 2026-06-09-chinese-router-plugin-plan.md
├── install.sh
├── scripts/
│   ├── cn2en.sh
│   └── en2cn.sh
└── skills/
    └── chinese-router/
        └── SKILL.md
```

#!/bin/bash
# en2cn.sh — Stop hook handler
# Reads stdin JSON, parses transcript JSONL for last assistant message,
# translates EN→CN via Claude subprocess, appends translation to output.
set -euo pipefail

# Guard against recursive translation: when we spawn claude --print for
# EN→CN translation, the Stop hook fires again for the child process.
# Skip hook processing in that context to prevent infinite loops.
if [ "${CHINESE_ROUTER_TRANSLATING:-}" = "1" ]; then
    cat
    exit 0
fi

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
translated=$(CHINESE_ROUTER_TRANSLATING=1 claude --print "$translation_prompt" 2>/dev/null)

if [ -n "$translated" ]; then
    printf '\n────────────────────\n%s\n' "$translated"
fi

#!/bin/bash
# en2cn.sh — Stop hook handler
# Reads stdin JSON, parses transcript JSONL for last assistant message,
# translates EN→CN via Claude subprocess, outputs JSON with systemMessage
# so the Chinese translation is shown to the user.
set -euo pipefail

# Guard against recursive translation: when we spawn claude --print for
# EN→CN translation, the Stop hook fires again for the child process.
# Skip hook processing in that context to prevent infinite loops.
if [ "${CHINESE_ROUTER_TRANSLATING:-}" = "1" ]; then
    echo '{}'
    exit 0
fi

# Read hook input from stdin
input=$(cat)
last_msg=$(echo "$input" | jq -r '.last_assistant_message // empty')
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Fall back to transcript parsing for older Claude Code versions or mock inputs
# that do not include last_assistant_message.
if [ -z "$last_msg" ] && [ -n "$transcript_path" ] && [ "$transcript_path" != "null" ] && [ -f "$transcript_path" ]; then
    # Extract last assistant text message from transcript JSONL.
    # assistant messages: {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "..."}, ...]}}
    last_msg=$(tail -100 "$transcript_path" 2>/dev/null | jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null | tail -1)
fi

# Skip if no assistant message found or message is too short
if [ -z "$last_msg" ] || [ ${#last_msg} -lt 10 ]; then
    echo '{}'
    exit 0
fi

# Translate EN→CN via Claude subprocess
translation_prompt=$(printf 'Translate the following English text to natural, fluent Chinese.\nOutput ONLY the Chinese translation without any explanation, quotes, or formatting.\n\n---\n%s' "$last_msg")
translated=$(CHINESE_ROUTER_TRANSLATING=1 claude --print "$translation_prompt" 2>/dev/null)

if [ -n "$translated" ]; then
    # Output JSON with systemMessage — shown as a system notification to the user
    jq -n --arg t "$translated" '{
      systemMessage: ("🇨🇳 \($t)")
    }'
else
    echo '{}'
fi

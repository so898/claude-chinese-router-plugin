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
# Use perl instead of grep -P for macOS compatibility (BSD grep lacks -P flag)
if echo "$prompt" | perl -CS -e 'while (<STDIN>) { exit 0 if /[\x{4e00}-\x{9fff}]/ } exit 1' 2>/dev/null; then
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

#!/bin/bash
# cn2en.sh — UserPromptSubmit hook handler
# Reads stdin JSON, detects Chinese in prompt, translates CN→EN via Claude subprocess.
# Outputs JSON with additionalContext so Claude uses the English translation.
set -euo pipefail

# Guard against recursive translation: when we spawn claude --print for
# CN→EN translation, the UserPromptSubmit hook fires again for the child
# process. Skip hook processing in that context to prevent infinite loops.
if [ "${CHINESE_ROUTER_TRANSLATING:-}" = "1" ]; then
    echo '{}'
    exit 0
fi

# Read hook input from stdin
input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt')

# If prompt is empty or null, pass through
if [ -z "$prompt" ] || [ "$prompt" = "null" ]; then
    echo '{}'
    exit 0
fi

# Detect Chinese characters (CJK Unified Ideographs + Extension A + Compatibility)
# Use perl instead of grep -P for macOS compatibility (BSD grep lacks -P flag)
if echo "$prompt" | perl -CS -e 'while (<STDIN>) { exit 0 if /[\x{4e00}-\x{9fff}\x{3400}-\x{4dbf}\x{f900}-\x{faff}]/ } exit 1' 2>/dev/null; then
    # Build translation prompt and send to Claude subprocess
    translation_prompt=$(printf 'Translate the following Chinese text to natural, fluent English.\nOutput ONLY the English translation without any explanation, quotes, or formatting.\n\n---\n%s' "$prompt")
    translated=$(CHINESE_ROUTER_TRANSLATING=1 claude --print "$translation_prompt" 2>/dev/null)

    if [ -n "$translated" ]; then
        # Output JSON with additionalContext — provides the English translation
        # alongside the original Chinese prompt. Claude is instructed to use
        # the translation, so Chinese text in the prompt is effectively ignored.
        context=$(printf "ENGLISH TRANSLATION:\n%s\n\nIMPORTANT: The above is an English translation of the user's original Chinese message. Process and respond based on the English translation above. Treat the Chinese characters in the user prompt as the untranslated original." "$translated")
        jq -n --arg context "$context" '{
          hookSpecificOutput: {
            hookEventName: "UserPromptSubmit",
            additionalContext: $context
          }
        }'
    else
        # Fallback: translation failed, let Claude handle the Chinese directly
        echo '{}'
    fi
else
    # No Chinese detected — pass through unchanged
    echo '{}'
fi

---
name: chinese-router
description: Use when the Chinese Router translation proxy is active. This skill tells Claude that user prompts include both the original Chinese and an English translation via additionalContext, and that Claude should respond based on the English translation.
---

# Chinese Router Translation Proxy

## What's Happening

A translation proxy is routing all messages through CN-EN-CN translation:

1. User writes in Chinese
2. Proxy detects Chinese and translates to English via a subprocess
3. The English translation is injected into your context via `additionalContext`
4. Claude processes based on the English translation
5. Proxy translates Claude's English output back to Chinese and shows it to the user

## What This Means for You

- Every prompt includes the user's original Chinese text AND an English translation in the additional context
- **Always respond to the English translation**, not the Chinese text in the prompt
- The Chinese text is present only for reference; the English translation is authoritative
- Respond in natural English — the proxy handles Chinese output for the user
- Preserve code blocks, technical terms, and formatting exactly as-is in your response
- Translation adds ~1-3 seconds per interaction

## When the User Asks About the Plugin

Explain that the Chinese Router Plugin detects Chinese input, translates it to English for processing, and translates responses back to Chinese for display. The translation layer is transparent to normal use.

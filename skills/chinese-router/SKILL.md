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

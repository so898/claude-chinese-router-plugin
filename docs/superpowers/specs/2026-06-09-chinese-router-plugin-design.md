# Chinese Router Plugin — Design Spec

## Problem

Claude 模型在处理中文指令和中文用户输入时表现会下降（"降智"）。用户需要在 Claude 完全看不到中文的前提下使用中文交互。

## Solution

通过 Claude Code Hooks 机制实现中英文双向翻译代理：

1. **UserPromptSubmit hook** — 用户输入中文 → `cn2en.sh` 检测中文并调用 Claude 子会话翻译 → 英文 prompt 送入主 Claude
2. Claude 全程用英文思考、执行、输出，完全看不见中文
3. **Stop hook** — 捕获 Claude 英文输出 → `en2cn.sh` 调用 Claude 子会话翻译 → 追加中文翻译到终端

翻译子会话使用 `--transient` 模式，翻译完成后自动删除。

## Architecture

```
User Input (CN)
    │
    ▼
UserPromptSubmit Hook
    │
    ├─ cn2en.sh detects CJK characters
    ├─ Spawns: claude -p "Translate to English: ..." (transient)
    └─ Replaces prompt with English
          │
          ▼
    Claude Main Session (English only)
          │
          ▼
    Terminal: English output ???
          │
          ▼
    Stop Hook
          │
    ├─ en2cn.sh captures English output
    ├─ Spawns: claude -p "Translate to Chinese: ..." (transient)
    └─ Appends Chinese translation
          │
          ▼
    Terminal: [English] + [Chinese]
```

## File Structure

```
claude-chinese-router-plugin/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata
├── skills/
│   └── chinese-router/
│       └── SKILL.md             # Skill instructions (optional, for awareness)
├── scripts/
│   ├── cn2en.sh                 # CN -> EN translation via Claude sub-session
│   └── en2cn.sh                 # EN -> CN translation via Claude sub-session
└── settings.local.json          # Hook configuration (project-level)
```

## Components

### 1. plugin.json

Standard Claude Code plugin manifest aligned with `~/.claude/plugins/` spec.

### 2. cn2en.sh (UserPromptSubmit hook)

- Reads user input from stdin or hook-provided argument
- Detects Chinese characters (Unicode range `一-鿿`)
- If Chinese found: calls `claude` CLI with translation prompt, captures output
- If no Chinese: passes through unchanged
- Outputs the translated English text as the result

Translation prompt format:
```
Translate the following Chinese text to natural, fluent English.
Output ONLY the English translation without any explanation, quotes, or formatting.

---
[original text]
```

### 3. en2cn.sh (Stop hook)

- Receives Claude's English output
- Calls `claude` CLI to translate back to Chinese
- Appends Chinese translation after a separator line
- Retains original English output above

Translation prompt format:
```
Translate the following English text to natural, fluent Chinese.
Output ONLY the Chinese translation without any explanation, quotes, or formatting.

---
[claude output]
```

### 4. SKILL.md (optional)

Lightweight skill metadata explaining the translation routing pattern.
May include: when to use, behavior expectations, known limitations.

## Hook Configuration

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "matcher": ".*",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/cn2en.sh"
    }],
    "Stop": [{
      "matcher": "",
      "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/en2cn.sh"
    }]
  }
}
```

## Unknowns to Resolve During Implementation

1. **Hook argument passing** — exact mechanism by which UserPromptSubmit receives user input and Stop receives Claude output
2. **Nested Claude invocation** — feasibility of calling `claude` CLI from within a Claude Code session
3. **Transient session flag** — precise CLI flag or equivalent for self-deleting sessions
4. **CJK detection** — whether to include Japanese/Korean characters or strictly Chinese
5. **Performance** — latency impact of two additional Claude API calls per interaction
6. **Edge cases** — mixed CN/EN input, code blocks, URLs, technical terms

# Chinese Router Plugin — Design Spec

## Problem

Claude 模型在处理中文指令和中文用户输入时表现可能下降。用户希望用中文交互，同时尽量让 Claude Code 基于英文译文理解和执行任务。

## Solution

通过 Claude Code Hooks 机制实现中英文双向翻译代理：

1. **UserPromptSubmit hook** — 用户输入中文 → `cn2en.sh` 检测中文并调用 Claude 子进程翻译 → 通过 `additionalContext` 注入英文译文和“优先使用译文”的指示
2. Claude 主会话仍会收到中文原文，但会同时收到英文译文作为优先参考
3. **Stop hook** — 读取 `last_assistant_message` → 翻译成中文 → 通过 `systemMessage` 展示给用户

翻译子进程通过 `CHINESE_ROUTER_TRANSLATING=1` 环境变量跳过本插件 hook，避免递归翻译循环。

## Architecture

### Data Flow

```
User Input (中文)
    │
    ▼
UserPromptSubmit Hook
    │  stdin: {"prompt": "帮我在 src/ 里建一个 utils.py", ...}
    │
    ├─ cn2en.sh:
    │    1. jq 解析 stdin JSON → 提取 prompt 字段
    │    2. 检测中文字符 (Unicode 一-鿿)
    │    3. CHINESE_ROUTER_TRANSLATING=1 claude --print "Translate to English: ..."
    │    4. stdout → JSON hookSpecificOutput.additionalContext
    │
    ▼
Claude Main Session
    收到: 中文原文 + additionalContext 中的英文译文
    按 hook 指示优先基于英文译文理解和执行
    │
    ▼
Terminal: 先展示 Claude 英文输出 (流式)
    │
    ▼
Stop Hook
    │  stdin: {"last_assistant_message": "I've completed...", "transcript_path": "...", ...}
    │
    ├─ en2cn.sh:
    │    1. jq 解析 stdin JSON → 优先提取 last_assistant_message
    │    2. 如缺失 last_assistant_message，再解析 JSONL transcript
    │    3. CHINESE_ROUTER_TRANSLATING=1 claude --print "Translate to Chinese: ..."
    │    4. stdout → JSON systemMessage
    │
    ▼
Terminal Output:
    [Claude 英文响应]
    [系统消息样式的中文翻译]
```

### Subprocess Interaction (nested `claude` call)

```
cn2en.sh / en2cn.sh
    │
    ├─ CHINESE_ROUTER_TRANSLATING=1  # 避免递归触发本插件 hook
    ├─ claude --print -p "..."       # 一次性翻译，不保留 session
    ├─ 读取 stdout 翻译结果
    └─ exit
```

### Translation Prompt Template

**CN → EN (cn2en.sh):**
```
Translate the following Chinese text to natural, fluent English.
Output ONLY the English translation without any explanation, quotes, or formatting.

---
[original Chinese text]
```

**EN → CN (en2cn.sh):**
```
Translate the following English text to natural, fluent Chinese.
Output ONLY the Chinese translation without any explanation, quotes, or formatting.

---
[Claude's English output]
```

## File Structure

```
claude-chinese-router-plugin/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata (for skill discovery)
├── skills/
│   └── chinese-router/
│       └── SKILL.md             # Skill instructions (lightweight, awareness)
├── scripts/
│   ├── cn2en.sh                 # UserPromptSubmit hook: CN → EN
│   └── en2cn.sh                 # Stop hook: EN → CN
├── install.sh                   # Inject hooks into ~/.claude/settings.json
├── uninstall.sh                 # Remove only this plugin's hooks
└── tests/run.sh                 # Regression tests
```

## Components

### 1. plugin.json

Standard Claude Code plugin manifest. Does NOT contain hook configuration (see Resolved Technical Details §6).

```json
{
  "name": "chinese-router",
  "description": "Chinese-English translation proxy via Claude Code hooks. Adds English translations to Chinese prompts and translates English responses back to Chinese.",
  "version": "1.0.0",
  "author": { "name": "Bill Cheng" },
  "license": "MIT"
}
```

### 2. cn2en.sh (UserPromptSubmit hook)

**Trigger:** Before Claude processes user input.

**Stdin JSON input:**
```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../session.jsonl",
  "cwd": "/current/working/dir",
  "permission_mode": "default",
  "hook_event_name": "UserPromptSubmit",
  "prompt": "用户输入的中文原文"
}
```

**Logic:**
1. `jq -r '.prompt'` 提取用户输入
2. 检测中文字符：`echo "$prompt" | grep -qP '[\x{4e00}-\x{9fff}]'`
3. 有中文 → `CHINESE_ROUTER_TRANSLATING=1 claude --print "Translate the following Chinese text to natural, fluent English. Output ONLY the English translation..." `
4. 无中文 → 输出空 JSON `{}`，不添加上下文
5. 有译文 → stdout 输出 JSON，包含 `hookSpecificOutput.hookEventName = "UserPromptSubmit"` 和 `additionalContext`

**Exit code:** 0（JSON 输出被 Claude Code 解析；`additionalContext` 会和原 prompt 一起进入上下文）

**Timeout:** 默认 30s，翻译任务足够

### 3. en2cn.sh (Stop hook)

**Trigger:** When Claude finishes responding and would wait for next input.

**Stdin JSON input:**
```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../session.jsonl",
  "cwd": "/current/dir",
  "permission_mode": "default",
  "hook_event_name": "Stop",
  "stop_reason": "end_turn",
  "last_assistant_message": "I've completed the refactoring..."
}
```

**Logic:**
1. `jq -r '.last_assistant_message // empty'` 获取最后助手消息
2. 如果该字段缺失，解析 JSONL transcript 获取最后一条 assistant 消息：
   ```bash
   tail -50 "$transcript_path" | jq -r 'select(.type == "assistant") | .message.content[] | select(.type == "text") | .text' | tail -1
   ```
   注意：`role` 嵌套在 `message.role` 中，非顶层字段；content 是数组格式
3. 如果提取到有效英文输出 → `CHINESE_ROUTER_TRANSLATING=1 claude --print "Translate to Chinese..."` (stdin 传入英文)
4. stdout 输出 JSON，包含 `systemMessage`

**Exit code:** 0（`systemMessage` 以系统消息样式展示给用户；普通 stdout 只进 debug log）

### 4. SKILL.md

轻量 Skill 元数据，告知 Claude 翻译代理的存在和行为预期。仅运行 `install.sh` 不会自动加载该 skill；它在通过 `--plugin-dir` 或插件安装加载本仓库时可作为补充指令。内容：
- 提醒主会话 Claude：用户的原始输入已被翻译为英文，对应中文翻译会展示给用户
- 说明用户可能看到中英文双份输出
- 如有必要，可以在用户可见的回复中保持英文风格

### 5. install.sh

**背景：** 已知 bug [anthropics/claude-code#10225](https://github.com/anthropics/claude-code/issues/10225) — `UserPromptSubmit` hook 定义在 Plugin 的 `hooks.json` 中不会被触发。变通方案是将 hook 配置直接写入全局 `~/.claude/settings.json`。

**功能：**
- 自动创建/更新 `~/.claude/settings.json`
- 注入 `UserPromptSubmit` 和 `Stop` hook 配置
- 保留已有字段和用户其他 hooks
- 重复运行时先移除本插件旧 hook，再写入一份新 hook

### 6. settings.json

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/path/to/claude-chinese-router-plugin/scripts/cn2en.sh\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/path/to/claude-chinese-router-plugin/scripts/en2cn.sh\""
          }
        ]
      }
    ]
  }
}
```

注意：
- Hook 配置不在 Plugin 的 `.claude-plugin/` 目录中（受 bug #10225 影响）
- `UserPromptSubmit` 不使用 `matcher` 字段
- `Stop` hook 通过 exit code 0 允许正常停止，中文翻译通过 `systemMessage` 展示

## Resolved Technical Details

### 1. Hook Input Format (stdin)

All hooks receive JSON on stdin. Common fields: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`.

| Hook | Extra Fields |
|------|-------------|
| UserPromptSubmit | `prompt` — user's submitted text |
| Stop | `stop_reason`, `last_assistant_message` |

Sources: [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks), [Hook Development SKILL.md](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md)

### 2. Prompt Augmentation (UserPromptSubmit)

Claude Code 的 `UserPromptSubmit` hook 不支持替换用户原始 prompt。Plain stdout 或 JSON `additionalContext` 会作为上下文和原始 prompt 一起传给 Claude。本项目使用 JSON `additionalContext` 注入英文译文。

Source: [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)

### 3. Nested Claude CLI Call

From hook scripts, spawning `claude` subprocesses also triggers hooks. Translation subprocesses set a guard environment variable so this plugin returns `{}` and does not recurse:

```bash
CHINESE_ROUTER_TRANSLATING=1 claude --print "translation instruction..."
```

Source: [anthropics/claude-agent-sdk-python#573](https://github.com/anthropics/claude-agent-sdk-python/issues/573), [canesin/coder#144](https://github.com/canesin/coder/issues/144)

### 4. Stop Message Extraction

Modern Claude Code Stop hook input includes `last_assistant_message`, so transcript parsing is only a fallback. When falling back, Claude Code stores conversation as JSONL at `transcript_path`. Assistant messages use nested format:

```json
{
  "type": "assistant",
  "message": {
    "role": "assistant",
    "content": [
      {"type": "text", "text": "actual response..."},
      {"type": "tool_use", ...}
    ]
  }
}
```

Key parsing gotchas: `role` is at `record.message.role` (not top-level); `content` is an array of blocks (not a string); filter `content[].type == "text"` to get response text.

Source: [Signet-AI/signetai#280](https://github.com/Signet-AI/signetai/issues/280), [tacogips/claude-code-agent#17](https://github.com/tacogips/claude-code-agent/issues/17)

### 5. CJK Detection

Use Unicode range `\\u4e00-\\u9fff` (CJK Unified Ideographs) for Chinese character detection. Sufficient for this use case — does not include Japanese kana or Korean hangul.

### 6. Plugin Hook Bug (#10225)

`UserPromptSubmit` hooks defined in plugin `hooks.json` match but do not execute. Workaround: define hooks directly in `~/.claude/settings.json` through `install.sh`. Other hook types (`Stop`, `PostToolUse`) work correctly from plugins.

Source: [anthropics/claude-code#10225](https://github.com/anthropics/claude-code/issues/10225)

### 7. Performance

Each user interaction adds 2 extra `claude` CLI calls (CN→EN + EN→CN). Translation is a small task (~100-500 tokens per call). Estimated latency increase: 1-3 seconds per call. Mentioned in SKILL.md as known behavior.

### 8. Edge Cases

| Scenario | Handling |
|----------|----------|
| Mixed CN/EN input | Detect Chinese → translate entire prompt; non-Chinese input passes through |
| Code blocks in user input | Translation prompt instructs to preserve code; Claude naturally handles this |
| URLs | Pass through — no translation needed |
| Technical terms | Claude translation naturally preserves technical terms |
| Very long user input | Claude handles; translation is a lightweight summarization task |

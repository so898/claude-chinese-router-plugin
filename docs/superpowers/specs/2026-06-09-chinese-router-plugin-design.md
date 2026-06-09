# Chinese Router Plugin — Design Spec

## Problem

Claude 模型在处理中文指令和中文用户输入时表现会下降（"降智"）。用户需要在 Claude 完全看不到中文的前提下使用中文交互。

## Solution

通过 Claude Code Hooks 机制实现中英文双向翻译代理：

1. **UserPromptSubmit hook** — 用户输入中文 → `cn2en.sh` 检测中文并调用 Claude 子进程翻译 → 英文 prompt 替换原始输入，送入主 Claude
2. Claude 全程用英文思考、执行、输出，完全看不见中文
3. **Stop hook** — 捕获 Claude 英文输出 → `en2cn.sh` 解析 transcript 获取最后助手消息 → 翻译成中文 → 追加到终端

翻译子进程通过 unset `CLAUDECODE` 环境变量实现嵌套 `claude` 调用。

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
    │    3. CLAUDECODE= claude -p "Translate to English: ..."
    │    4. stdout → 英文 prompt 替换原始输入
    │
    ▼
Claude Main Session (English only)
    收到: "Create a utils.py in src/"
    全程英文思考、执行、流式输出
    │
    ▼
Terminal: 先展示 Claude 英文输出 (流式)
    │
    ▼
Stop Hook
    │  stdin: {"transcript_path": "/path/to/session.jsonl", "stop_reason": "end_turn", ...}
    │
    ├─ en2cn.sh:
    │    1. jq 解析 stdin JSON → 提取 transcript_path
    │    2. 解析 JSONL transcript → 获取最后一条 assistant 消息的 text 内容
    │    3. CLAUDECODE= claude -p "Translate to Chinese: ..."
    │    4. stdout → 中文翻译追加显示
    │
    ▼
Terminal Final Output:
    [Claude 英文响应]
    ────────────────────
    [中文翻译]
```

### Subprocess Interaction (nested `claude` call)

```
cn2en.sh / en2cn.sh
    │
    ├─ unset CLAUDECODE              # 避免 "cannot launch inside another session" 错误
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
├── settings.local.json          # Hook configuration (project-level, gitignored)
└── install.sh                   # One-shot: inject hooks into settings.local.json
```

## Components

### 1. plugin.json

Standard Claude Code plugin manifest. Does NOT contain hook configuration (see Resolved Technical Details §6).

```json
{
  "name": "chinese-router",
  "description": "Chinese-English translation proxy via Claude Code hooks. Prevents Chinese text from reaching the main Claude session to avoid degraded performance on Chinese-language tasks.",
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
3. 有中文 → `CLAUDECODE= claude --print -p "Translate the following Chinese text to natural, fluent English. Output ONLY the English translation..." ` (stdin 传入原文)
4. 无中文 → echo 原文（透传）
5. stdout 输出最终 prompt

**Exit code:** 0（stdout 内容替换 Claude 看到的 prompt）

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
  "stop_reason": "end_turn"
}
```

**Logic:**
1. `jq -r '.transcript_path'` 获取 transcript 路径
2. 解析 JSONL transcript 获取最后一条 assistant 消息：
   ```bash
   tail -50 "$transcript_path" | jq -r 'select(.type == "assistant") | .message.content[] | select(.type == "text") | .text' | tail -1
   ```
   注意：`role` 嵌套在 `message.role` 中，非顶层字段；content 是数组格式
3. 如果提取到有效英文输出 → `CLAUDECODE= claude --print -p "Translate to Chinese..."` (stdin 传入英文)
4. 打印分隔线和中文翻译到 stdout

**Exit code:** 0（stdout 内容出现在 transcript 中，用户可见）

### 4. SKILL.md

轻量 Skill 元数据，告知 Claude 翻译代理的存在和行为预期。内容：
- 提醒主会话 Claude：用户的原始输入已被翻译为英文，对应中文翻译会展示给用户
- 说明用户可能看到中英文双份输出
- 如有必要，可以在用户可见的回复中保持英文风格

### 5. install.sh

**背景：** 已知 bug [anthropics/claude-code#10225](https://github.com/anthropics/claude-code/issues/10225) — `UserPromptSubmit` hook 定义在 Plugin 的 `hooks.json` 中不会被触发。变通方案是将 hook 配置直接写入 `settings.local.json`。

**功能：**
- 在项目根目录自动创建/更新 `.claude/settings.local.json`
- 注入 `UserPromptSubmit` 和 `Stop` hook 配置
- 保留已有字段，只追加/更新 hooks 部分

### 6. settings.local.json

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/claude-chinese-router-plugin/scripts/cn2en.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/claude-chinese-router-plugin/scripts/en2cn.sh"
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
- `Stop` hook 通过 exit code 0 允许正常停止，stdout 内容追加到 transcript

## Resolved Technical Details

### 1. Hook Input Format (stdin)

All hooks receive JSON on stdin. Common fields: `session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`.

| Hook | Extra Fields |
|------|-------------|
| UserPromptSubmit | `prompt` — user's submitted text |
| Stop | `stop_reason` — why Claude stopped |

Sources: [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks), [Hook Development SKILL.md](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md)

### 2. Prompt Replacement (UserPromptSubmit)

Printing plain text to stdout (exit 0) **replaces** the user's original prompt. This is the mechanism cn2en.sh uses to swap Chinese for English.

Source: [Rewrite Prompts on the Fly with UserPromptSubmit Hooks](https://egghead.io/lessons/rewrite-prompts-on-the-fly-with-user-prompt-submit-hooks~76rrt)

### 3. Nested Claude CLI Call

From hook scripts, spawning `claude` subprocesses requires unsetting the `CLAUDECODE` environment variable to bypass the nested session guard (introduced in v2.1.39, Feb 2026):

```bash
CLAUDECODE= claude --print -p "translation instruction" <<< "$text_to_translate"
```

Source: [anthropics/claude-agent-sdk-python#573](https://github.com/anthropics/claude-agent-sdk-python/issues/573), [canesin/coder#144](https://github.com/canesin/coder/issues/144)

### 4. Transcript Parsing (Stop Hook)

Claude Code stores conversation as JSONL at `transcript_path`. Assistant messages use nested format:
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

`UserPromptSubmit` hooks defined in plugin `hooks.json` match but do not execute. Workaround: define hooks directly in `settings.local.json` (project-level, gitignored). Other hook types (`Stop`, `PostToolUse`) work correctly from plugins. `install.sh` automates the settings injection.

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

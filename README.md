# Chinese Router Plugin

Claude Code 的中英文翻译代理插件。通过 Hook 机制在 Claude 处理之前将用户的中文输入翻译为英文，处理完毕后再将英文输出翻译回中文，从而避免 Claude 模型在处理中文时性能下降。

## 工作原理

```
用户输入（中文）
    │
    ▼
UserPromptSubmit Hook → cn2en.sh
    │  检测到中文 → 调用 Claude 翻译成英文
    │  通过 additionalContext 将英文翻译注入 Claude 上下文
    │  同时 SKILL.md 指示 Claude 使用英文翻译而非中文原文
    ▼
Claude 主会话（基于英文翻译工作，中文原文仅作为参考）
    │
    ▼
终端显示英文输出
    │
    ▼
Stop Hook → en2cn.sh
    │  解析 transcript 获取最后一条助手消息 → 翻译成中文
    │  通过 systemMessage 将中文翻译展示给用户
    ▼
终端显示中文翻译（系统消息）
```

> **技术说明：** Claude Code 的 UserPromptSubmit hook **不支持直接替换 prompt 文本**，只能通过 `additionalContext` 注入附加上下文。因此英文翻译会与中文原文一同传递给 Claude，但本插件通过 SKILL.md 指示 Claude 以英文翻译为准。Stop hook 的 stdout 仅写入 debug log，因此翻译结果通过 `systemMessage` 字段展示给用户。

每次交互会额外产生 2 次轻量级 Claude 调用（翻译任务），延迟约 1-3 秒。

## 前置要求

- [Claude Code](https://claude.com/claude-code) 已安装并可正常使用
- `jq` 命令行 JSON 处理工具（`brew install jq`）
- `perl`（macOS / Linux 自带）

## 安装

### 1. 克隆仓库

```bash
git clone https://github.com/so898/claude-chinese-router-plugin.git
```

### 2. 运行安装脚本

```bash
bash /path/to/claude-chinese-router-plugin/install.sh
```

安装脚本会将 Hook 配置写入全局配置 `~/.claude/settings.json`，与已有配置合并，不会覆盖 `permissions`、`enabledPlugins` 等现有字段：

```json
{
  "permissions": { "...": "保持不变" },
  "enabledPlugins": { "...": "保持不变" },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/.../scripts/cn2en.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/.../scripts/en2cn.sh"
          }
        ]
      }
    ]
  }
}
```

安装完成后，**所有** Claude Code 项目都会自动启用翻译代理。

> **注意：** Hook 配置写在 `~/.claude/settings.json` 而非 Plugin 目录，这是为了规避 Claude Code 已知 bug（[#10225](https://github.com/anthropics/claude-code/issues/10225)），该 bug 会导致 Plugin 中的 UserPromptSubmit hook 无法触发。

### 3. 开始使用

正常启动 Claude Code，用中文输入即可。翻译代理会自动生效。

## 使用方法

### 正常使用

直接用中文与 Claude Code 交互，翻译代理会在后台自动完成双向翻译：

```
$ claude
> 帮我在 src 目录下创建一个 utils.py 文件

# Claude 收到的是：中文原文 + 英文翻译（通过 additionalContext 注入）
# Claude 根据英文翻译理解指令，用英文思考并执行
# 终端先展示英文输出，然后通过系统消息展示中文翻译
```

### 混合输入

如果输入不包含中文字符，翻译脚本会自动透传，无额外开销：

```
> Create a test file for the auth module
# 直接传给 Claude，不做翻译
```

### 验证插件是否生效

在 Claude Code 会话中提交一条中文 prompt，观察：
1. Claude 应能正确理解并响应中文指令（说明英文翻译注入成功）
2. 响应结束后会出现一条系统消息，其中包含中文翻译

如果 Claude 无法理解中文输入，或没有出现中文翻译系统消息，请检查 `~/.claude/settings.json` 中的 hooks 配置和脚本路径是否正确。

## 卸载

### 方式一：使用卸载脚本（推荐）

```bash
bash /path/to/claude-chinese-router-plugin/uninstall.sh
```

卸载脚本会自动从 `~/.claude/settings.json` 中移除 Chinese Router 的 hook 配置，保留其他设置不变。

### 方式二：手动移除

编辑 `~/.claude/settings.json`，删除 `hooks.UserPromptSubmit` 和 `hooks.Stop` 中属于 Chinese Router 的条目。

如果 hooks 对象仅剩 Chinese Router 的配置，直接删除整个 hooks 字段：

```bash
jq 'del(.hooks.UserPromptSubmit) | del(.hooks.Stop)' ~/.claude/settings.json > /tmp/settings.json && \
  mv /tmp/settings.json ~/.claude/settings.json
```

### 删除插件文件

```bash
rm -rf /path/to/claude-chinese-router-plugin
```

## 文件结构

```
claude-chinese-router-plugin/
├── .claude-plugin/
│   └── plugin.json              # 插件元信息
├── .gitignore
├── README.md
├── install.sh                   # 安装脚本（写入 ~/.claude/settings.json）
├── uninstall.sh                 # 卸载脚本
├── scripts/
│   ├── cn2en.sh                 # 中→英翻译（UserPromptSubmit hook）
│   └── en2cn.sh                 # 英→中翻译（Stop hook）
└── skills/
    └── chinese-router/
        └── SKILL.md             # 技能定义
```

## 常见问题

**Q: 翻译延迟很大怎么办？**

翻译调用使用的是 Claude Code 配置的模型。如果延迟过高，可以检查网络连接或换用更快的模型。

**Q: 代码块和 URL 被翻译了怎么办？**

不会。翻译 prompt 会指示 Claude 保持代码和技术内容原样输出，Claude 能自动识别并保留。

**Q: 为什么我的中文输入还是会传给 Claude？**

Claude Code 的 UserPromptSubmit hook **不支持直接替换 prompt 文本**——这是 Claude Code 本身的限制。本插件通过 `additionalContext` 注入英文翻译，并由 SKILL.md 指示 Claude 以英文翻译为准进行响应。中文原文对 Claude 的推理质量影响很小，因为 SKILL.md 和 additionalContext 中的指令会引导 Claude 优先使用英文翻译。

**Q: 为什么翻译结果显示为系统消息（警告样式）？**

Stop hook 的 stdout 仅写入 debug log，无法直接展示给用户。因此翻译结果通过 `systemMessage` JSON 字段输出，在终端上会以系统消息样式显示。这是 Claude Code hook 机制下的最佳可用方案。

**Q: 为什么我的 UserPromptSubmit hook 不触发？**

这是 Claude Code 的已知 bug（[#10225](https://github.com/anthropics/claude-code/issues/10225)）。本插件将 hook 配置写在 `~/.claude/settings.json` 中绕过此问题。如果你手动把配置移到了 plugin 目录，请改回来。

**Q: 只想翻译输入不想翻译输出怎么办？**

编辑 `~/.claude/settings.json`，删掉 `hooks.Stop` 中 Chinese Router 的条目。

**Q: 只想在特定项目启用怎么办？**

将 `~/.claude/settings.json` 中的 hooks 配置移动到目标项目的 `.claude/settings.local.json` 即可。全局安装后再手动调整。

## 致谢

感谢 [0xBB2B](https://github.com/0xBB2B) 参与早期测试，其 Claude Max 账号额度在该过程中不幸耗尽——正是因为本插件翻译子进程递归触发的翻译循环 bug（现已修复：`cn2en.sh` 和 `en2cn.sh` 在翻译子进程中设置 `CHINESE_ROUTER_TRANSLATING=1` 环境变量并检查跳过，杜绝递归调用）。

## 许可

MIT

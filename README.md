# Chinese Router Plugin

Claude Code 的中英文翻译代理插件。通过 Hook 机制在 Claude 处理之前将用户的中文输入翻译为英文，处理完毕后再将英文输出翻译回中文，从而避免 Claude 模型在处理中文时性能下降。

## 工作原理

```
用户输入（中文）
    │
    ▼
UserPromptSubmit Hook → cn2en.sh
    │  检测到中文 → 调用 Claude 翻译成英文 → 替换原始 prompt
    ▼
Claude 主会话（全程英文，零中文接触）
    │
    ▼
终端显示英文输出
    │
    ▼
Stop Hook → en2cn.sh
    │  解析 transcript 获取最后一条助手消息 → 翻译成中文
    ▼
终端追加显示中文翻译
```

每次交互会额外产生 2 次轻量级 Claude 调用（翻译任务），延迟约 1-3 秒。

## 前置要求

- [Claude Code](https://claude.com/claude-code) 已安装并可正常使用
- `jq` 命令行 JSON 处理工具
- `perl`（macOS / Linux 自带）

## 安装

### 1. 克隆仓库

```bash
git clone https://github.com/<your-org>/claude-chinese-router-plugin.git
cd claude-chinese-router-plugin
```

### 2. 运行安装脚本

在**你要使用中文翻译代理的项目根目录**下运行：

```bash
bash /path/to/claude-chinese-router-plugin/install.sh
```

安装脚本会将 Hook 配置写入项目级 `.claude/settings.local.json`：

```json
{
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

> **注意：** Hook 配置写在项目本地的 `settings.local.json`，而非 Plugin 目录，这是为了规避 Claude Code 已知 bug（[#10225](https://github.com/anthropics/claude-code/issues/10225)），该 bug 会导致 Plugin 中的 UserPromptSubmit hook 无法触发。

### 3. 开始使用

在该项目中正常启动 Claude Code 即可。插件会自动生效，无需额外操作。

## 使用方法

### 正常使用

直接用中文与 Claude Code 交互，翻译代理会在后台自动完成双向翻译：

```
$ claude
> 帮我在 src 目录下创建一个 utils.py 文件

# Claude 收到的是英文翻译，用英文思考并执行
# 终端先展示英文输出
# 然后再追加中文翻译
```

### 混合输入

如果输入不包含中文字符，翻译脚本会自动透传，无额外开销：

```
> Create a test file for the auth module
# 直接传给 Claude，不做翻译
```

### 验证插件是否生效

在 Claude Code 会话中提交一条中文 prompt，观察：
1. 终端会先显示 Claude 的英文响应
2. 英文响应下方会出现 `────` 分隔线和中文字幕

如果只看到英文输出且没有中文翻译，请检查 `.claude/settings.local.json` 中的脚本路径是否正确。

## 卸载

### 移除 Hook 配置

编辑项目下的 `.claude/settings.local.json`，删除 `hooks` 字段中与 Chinese Router 相关的配置：

```bash
# 方式一：手动编辑
vim .claude/settings.local.json

# 方式二：用 jq 一键清除 hooks
jq 'del(.hooks)' .claude/settings.local.json > .claude/settings.local.json.tmp && \
  mv .claude/settings.local.json.tmp .claude/settings.local.json
```

如果 settings.local.json 只有 hooks 配置，直接删除文件即可：

```bash
rm .claude/settings.local.json
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
├── install.sh                   # 安装脚本
├── scripts/
│   ├── cn2en.sh                 # 中→英翻译（UserPromptSubmit hook）
│   └── en2cn.sh                 # 英→中翻译（Stop hook）
├── skills/
│   └── chinese-router/
│       └── SKILL.md             # 技能定义
└── README.md
```

## 常见问题

**Q: 翻译延迟很大怎么办？**

翻译调用使用的是 Claude Code 配置的模型。如果延迟过高，可以检查网络连接或换用更快的模型。

**Q: 代码块和 URL 被翻译了怎么办？**

不会。翻译 prompt 会指示 Claude 保持代码和技术内容原样输出，Claude 能自动识别并保留。

**Q: 为什么我的 UserPromptSubmit hook 不触发？**

这是 Claude Code 的已知 bug（[#10225](https://github.com/anthropics/claude-code/issues/10225)）。本插件已将 hook 配置写在 `settings.local.json` 中绕过此问题。如果你手动把配置移到了 plugin 目录，请改回 `settings.local.json`。

**Q: 只想翻译输入不想翻译输出怎么办？**

编辑 `.claude/settings.local.json`，删掉 `Stop` hook 配置块即可。

## 许可

MIT

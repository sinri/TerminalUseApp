# Terminal Use APP

在一个桌面工作区管理本地终端、SSH 连接，并让 AI Agent 辅助完成命令行任务。左侧切换终端，右侧与 Agent 对话；执行命令前可以查看解释、风险评估并决定是否允许。

- 多终端标签页，支持改名、复制粘贴、中文输入与 Nerd Font 图标。
- 保存 SSH 入口，使用密钥或密码连接；macOS 密码可保存到系统钥匙串。
- 接入你自己的模型服务，支持 OpenAI-compatible 和 Anthropic 协议、Skills 及会话历史。
- 为外部 Agent 提供 MCP 接入，按终端 ID 定向操作。

## 下载安装

前往 [GitHub Releases](https://github.com/sinri/TerminalUseApp/releases/latest)，下载 DMG，打开后将 **Terminal Use APP** 拖入 **Applications**。

Windows **1.1.0+2** 提供 x64 ZIP 包，完整解压后运行 `terminal_use_app.exe`，保留相邻 DLL 和 data 目录。支持选择 PowerShell、CMD、Git Bash、WSL 和自定义 Shell。设置顶部可打开关于与许可证。

macOS [**1.1.0+3**](https://github.com/sinri/TerminalUseApp/releases/tag/v1.1.0%2B3) 支持 **macOS 12.0 或更高版本 / Apple Silicon（arm64）**。DMG 已使用 Developer ID 签名，通过 Apple 公证并装订票据。请在 Releases 中选择对应平台的发行版本。

当前没有 Intel macOS 或 Linux 发行包。普通使用无需安装 Flutter 或 Xcode；SSH 使用系统 OpenSSH，外部 MCP 需要 Python 3。仓库为私有时，下载需要仓库访问权限。

## 快速上手

1. 打开 App，点击“新建终端”。启动时工作区为空，不会自动创建 shell。
2. 直接使用终端；如需 SSH，在“SSH 设置”中保存连接，再从新建菜单打开。
3. 使用 AI 辅助时，在 Agent 设置中添加模型服务地址、认证和模型。模型须支持工具调用，服务及费用由你自行配置。
4. 选中目标终端，在右侧选择模型并输入任务，按 **⌘Return** 发送；输入框中的 `@` 可选择目标终端。
5. 查看待执行操作的解释和风险，点击“允许本次执行”或拒绝。默认各风险等级均需确认。

“停止”会停止后续 Agent 操作；已经提交的 shell 命令可在对应终端按 **Ctrl+C** 中断。关闭终端会结束对应会话，自行脱离会话的后台进程可能继续运行。

## 常用快捷键

| 操作 | macOS 快捷键 |
| --- | --- |
| 新建终端 | ⌘T |
| 关闭当前终端 | ⌘W |
| 打开设置 | ⌘, |
| 上一个 / 下一个终端 | ⌘⌥← / ⌘⌥→ |
| 聚焦 Agent 输入 | ⌘⇧A |
| 发送任务（Enter 换行） | ⌘Return |

## 权限与数据

Agent 使用当前用户权限执行命令，风险评估和确认卡片不提供系统隔离。请只允许你理解的操作，只把 MCP 连接参数交给受信任的客户端。

模型服务会收到任务相关的对话、终端输出和 Skills 内容。API Key 保存在本地配置文件，SSH 密码在 macOS 保存在系统钥匙串；会话历史可能包含业务数据。分享日志、截图或反馈前请删除敏感内容。

## 使用帮助与反馈

- [完整使用指南](docs/user-guide.md)：SSH、模型、Skills、会话绑定、本地数据位置与常见问题。
- [外部 Agent / MCP 接入](docs/mcp.md)：连接配置和终端工具用法。
- [更新记录](CHANGELOG.md)：版本变化。
- [反馈问题](https://github.com/sinri/TerminalUseApp/issues)：请附 App 版本、macOS 版本、CPU 架构和复现步骤。

开发、架构及发行维护文档统一从 [文档导航](docs/README.md) 进入。

## 开源许可证

本项目原创代码采用 [GNU GPL v3.0（仅限该版本）](LICENSE)。第三方组件和字体保留各自许可证，可在 App 的“关于 → 许可证与第三方声明”中查看；清单见 [依赖许可证记录](docs/dependency-licenses.md)。

# Terminal Use

Flutter 桌面多终端与运维 Agent 工作区。左侧纵向 Tab 管理本地 shell 和 SSH，右侧可运行内置 LLM Agent。HTTP / MCP 使用稳定终端 ID 定向操作；切换 Tab 不改变任务目标。拖动终端和 Agent 之间的分隔条调整宽度。

## 启动

需要 Flutter、对应桌面平台构建工具；macOS 最低 12.0，另需 Xcode 和 CocoaPods。

```sh
flutter pub get
flutter run -d macos
# Linux / Windows 分别使用 -d linux / -d windows
```

```sh
flutter build macos --release
flutter analyze
flutter test
# 真实桌面 UI + Python MCP → HTTP → PTY 集成测试（需要 Python 3）
flutter test integration_test/terminal_test.dart -d macos
```

本机 Flutter 3.41.5 与 Xcode 的通用架构检查存在兼容问题；若 Release 报 `does not contain architectures "arm64 x86_64"`，Apple Silicon 可在执行上述 Flutter build 后改用：

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release -derivedDataPath build/macos -quiet ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

产物位于 `build/macos/Build/Products/Release/terminal_use_app.app`。

当前在 macOS 开发验证，Linux/Windows 已生成平台工程，但尚未在对应系统验证。默认启动登录 shell（Windows 为 PowerShell），工作目录为用户 HOME。支持 ANSI、中文、交互程序、键盘输入、窗口尺寸同步和 Ctrl+C。内置等宽 Nerd Fonts Symbols 回退字体，支持 agnoster 等 zsh 主题的 Powerline / Nerd Font 图标，无需额外安装系统字体。关闭 app 会向终端和 agent 进程发送终止信号；自行脱离会话的后台进程可能继续运行。

## 多终端与 SSH

左侧 `New` 新建 shell，点击 Tab 切换，双击或长按名称改名，关闭按钮终止对应会话。终端支持选中后复制、通过右键菜单粘贴，沿用 xterm 的平台键盘快捷键。Tab 的 `terminal-N` 是本次运行中的稳定 ID，关闭后不复用。

在左下角「SSH 设置」中添加入口，随后从 New 旁的下拉菜单打开。支持用户名、端口、默认 `~/.ssh/id_rsa` 或自定义密钥路径，以及密码登录。密码在 SSH 终端交互输入，不保存；保留系统 OpenSSH 的主机指纹确认。自动设置 `ServerAliveInterval=30` 与 `ServerAliveCountMax=3`。SSH 可执行程序需已在系统 PATH 中。

macOS 退出时先停止桥接、内部 Agent 与各 PTY，再退出进程。关闭 Tab 会向同一 PTY 下的进程发送挂断信号；`nohup` 或自行脱离会话的进程可以继续运行。

## 内部 Agent 与 Skills

1. 在设置中添加一个或多个 LLM 配置，填写服务地址（如 `https://host`，默认使用 `/v1`）或 API 基础地址（如 `https://host/gateway/v1`），也可填写标准完整请求地址。每组 Endpoint 和 API Key 只需配置一次。点击「从 API 加载模型」后保存，或每行手填一个模型 ID。所有已保存的模型都可在右侧按消息选择。
2. 支持 **OpenAI-compatible Chat Completions**（例如 `https://host/v1/chat/completions`）和 **Anthropic Messages**（例如 `https://host/v1/messages`）。认证支持 Bearer、`x-api-key` 或无认证。要求模型支持工具调用，当前使用非流式响应。
3. 可填写 Skills 根目录（支持 `~/`）。任务开始时递归发现 `SKILL.md`，将名称和描述提供给模型；模型通过 `skill_read` 按需读取全文。最多 200 个 Skill，单文件最多 128 KiB，不跟随目录符号链接，不允许读取根目录外的文件。Skill 附属脚本可由模型根据指引通过已授权的终端调用。
4. 在右侧底部选择模型、填写任务并点击「发送」。当前会话保留上下文，右上角可新建会话。任务绑定开始时选中的终端，最多 40 轮；工具调用和回复显示在日志中。关闭目标 Tab 后任务停止。点击「停止」会停止后续工具调用；已提交的 shell 命令可用终端 Ctrl+C 中断。

配置保存在 `~/.terminal-use/settings.json`（Windows 使用 `%APPDATA%/.terminal-use/settings.json`），Unix 目录权限 700、文件权限 600。API Key 保存在此本地文件中，输入界面隐藏显示。终端内容与 Skills 会发送给用户配置的模型 Endpoint；运行日志仅保存在本次内存中。当前不包含会话历史持久化和系统钥匙串集成。

在输入框中键入 `@` 可按 Tab 名称或 ID 选择目标。发送前无需手写 ID。

Agent 的每次终端写入（含交互按键和 Ctrl+C）都先通过当前模型的独立请求评估，再在 Agent 上下文区显示目标、原始输入、风险等级和理由。卡片分别展示命令解释和风险依据。默认三个等级均须点击「允许本次执行」才发送。在 Agent 设置中，可针对低、中、高风险分别开启自动放行，开启后匹配该等级的操作直接执行。确认卡片持续等待你决定，打开设置时也会保留。拒绝、取消操作或评估失败均不写入。外部 MCP 写入也需此确认，风险评估使用所选模型（未选择时使用首个配置），待执行输入会发送到该模型的 Endpoint。

## Terminal MCP

从 Agent 设置页复制本次运行的连接参数，在独立客户端的 MCP 进程环境中设置 `TERMINAL_USE_URL` 和 `TERMINAL_USE_TOKEN`。使用 Python 3 执行本项目的 `tools/terminal_bridge.py mcp` 即可通过 stdio 访问终端。重启应用后需更新连接参数。

执行 shell 命令使用 `terminal_run`，例如 `{"terminal_id":"terminal-1","command":"pwd"}`。工具会自动提交回车，随后用 `terminal_read` 查看结果。交互程序需要逐键输入时使用 `terminal_input`。

## HTTP API

所有请求都必须携带 `Authorization: Bearer <TERMINAL_USE_TOKEN>`。

| 方法 | 路径 | 行为 |
| --- | --- | --- |
| GET | `/terminals` | 枚举当前 Tab 的 ID、名称和运行状态 |
| GET | `/terminal?terminal_id=terminal-1` | 返回渲染后的终端 buffer 文本、PID、进程状态、退出码和行列数 |
| POST | `/input?terminal_id=terminal-1` | JSON `{"text":"pwd\r"}`；向 PTY 写入精确输入，最大 64 KiB |
| POST | `/interrupt?terminal_id=terminal-1` | 发送 Ctrl+C |

省略 `terminal_id` 时保留旧接口语义，固定操作应用最初的终端，关闭后返回错误，不会跟随选中 Tab 或转到其他终端。新接入应始终指定 ID。

`/terminal` 返回指定终端的当前活动 buffer（最多 10000 行），全屏程序显示当前屏幕，不保证包含已离开屏幕的历史。API 不提供单条命令退出码；`exitCode` 是 shell 的退出码。输入与读取均非事务操作，人和 agent 同时输入可能交错。

## 权限

这是本地 shell 工具：agent 和人工终端具有当前用户权限。令牌持有者可执行本地命令，并读取终端中的敏感输出。只给受信任的 agent 连接参数。macOS 为运行任意本地 shell，Debug / Release 已关闭 App Sandbox；这不是 Mac App Store 沙盒应用。

终端组件采用 [xterm](https://pub.dev/packages/xterm) 和 [flutter_pty](https://pub.dev/packages/flutter_pty)。

图标回退字体：[Nerd Fonts Symbols Mono v3.4.0](https://github.com/ryanoasis/nerd-fonts/tree/v3.4.0/patched-fonts/NerdFontsSymbolsOnly)。字体原样打包，许可证见 `assets/fonts/NERD-FONTS-LICENSE.txt`。

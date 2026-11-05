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

Release / Profile 默认按构建机器的本机架构生成（Apple Silicon 为 arm64，Intel 为 x86_64），配置位于 `macos/Runner/Configs/Release.xcconfig`。这是为了规避本机 Xcode `lipo -verify_arch arm64 x86_64` 的参数兼容问题；标准 `flutter build macos --release` 和 IDE 的 Release 运行均可直接使用。当前默认产物不是通用双架构包；跨架构分发需在解决工具链问题后另行构建验证。

产物位于 `build/macos/Build/Products/Release/terminal_use_app.app`。

本机 Flutter 3.41.5 的 `flutter run --release` 在 App 退出后可能继续等待，导致 IDE 的运行状态未结束。推荐在 IDE Terminal 或 Shell Script 运行配置中使用：

```sh
./tools/run_macos_release.sh
# 如果 Flutter 不在 PATH 中：
FLUTTER_BIN=/path/to/flutter/bin/flutter ./tools/run_macos_release.sh
```

脚本先生成 Flutter Release 配置，使用明确的本机 Xcode destination 构建，再以 `exec` 运行 App。关窗后命令随 App 进程退出，且不会触发 Any Mac 占位目标的版本 warning。此方式不使用 Flutter IDE 调试协议；调试仍用普通 Debug 运行配置。本方案只修改项目文件。


Flutter 3.47.9 使用默认的合并 UI / 平台线程，已移除针对 Flutter 3.41 的 `FLTEnableMergedPlatformUIThread=false` 旧兼容开关；新 SDK 已弃用分离线程。IDE 的 `--machine --start-paused` 会在入口暂停，需调试器继续运行后才绘制 Dart 首屏。

`flutter_pty` 暂时保持 pub.dev 0.4.2 与 CocoaPods 构建，项目 `pubspec.yaml` 禁用 SPM 集成，避免未完成迁移影响终端动态库加载。Flutter 3.47.9 仍可能输出插件缺少 SPM 支持的警告；迁移验证完成前保留此提示。原生依赖切换后需停止应用并重新编译，热重载不足以更新动态库。

当前在 macOS 开发验证，Linux/Windows 已生成平台工程，但尚未在对应系统验证。启动时显示空工作区，不自动创建标签页或 shell。点击「新建终端」后启动登录 shell（Windows 为 PowerShell），工作目录为用户 HOME。支持 ANSI、中文、交互程序、键盘输入、窗口尺寸同步和 Ctrl+C。内置等宽 Nerd Fonts Symbols 回退字体，支持 agnoster 等 zsh 主题的 Powerline / Nerd Font 图标，无需额外安装系统字体。关闭 app 会向终端和 agent 进程发送终止信号；自行脱离会话的后台进程可能继续运行。

## 桌面交互

使用紧凑的 mac 风格控件、原生 macOS「终端」菜单和设置弹窗。⌘T 新建终端、⌘W 关闭当前标签页、⌘, 打开设置、⌘⌥←/→ 切换终端；⌘⇧A 聚焦 Agent，⌘Return 发送任务，普通 Enter 换行。侧栏支持右键操作、双击/F2 改名；分隔条支持拖动、聚焦后方向键调整、Home/双击恢复。终端接入标准文本输入法通道。详细规范见 [桌面界面规范](docs/ui-design.md)。

## 多终端与 SSH

左侧 `New` 新建 shell，点击 Tab 切换，双击或长按名称改名，关闭按钮终止对应会话。终端支持选中后复制、通过右键菜单粘贴，沿用 xterm 的平台键盘快捷键。Tab 的 `terminal-N` 是本次运行中的稳定 ID，关闭后不复用。

在左下角「SSH 设置」中添加入口，随后从 New 旁的下拉菜单打开。支持用户名、端口、默认 `~/.ssh/id_rsa` 或自定义密钥路径，以及密码登录。密码在 SSH 终端交互输入，不保存；保留系统 OpenSSH 的主机指纹确认。自动设置 `ServerAliveInterval=30` 与 `ServerAliveCountMax=3`。SSH 可执行程序需已在系统 PATH 中。

macOS 关窗和 ⌘Q 共用退出流程：保持 Flutter 引擎存活，先停止内部 Agent，并行关闭桥接与各 PTY，再退出进程。正常清理完成后立即退出；Dart 暂停或失联时，原生端在约 2 秒后结束等待，避免无限挂住（此时不能保证所有清理已完成）。关闭 Tab 会向同一 PTY 下的进程发送挂断信号；`nohup` 或自行脱离会话的进程可以继续运行。

## 内部 Agent 与 Skills

1. 在设置中添加一个或多个 LLM 配置，填写服务地址（如 `https://host`，默认使用 `/v1`）或 API 基础地址（如 `https://host/gateway/v1`），也可填写标准完整请求地址。每组 Endpoint 和 API Key 只需配置一次。点击「从 API 加载模型」后保存，或每行手填一个模型 ID。所有已保存的模型都可在右侧按消息选择。
2. 支持 **OpenAI-compatible Chat Completions**（例如 `https://host/v1/chat/completions`）和 **Anthropic Messages**（例如 `https://host/v1/messages`）。认证支持 Bearer、`x-api-key` 或无认证。要求模型支持工具调用。主对话与风险评估均发送 `stream: true` 接收 SSE，正文逐步显示；工具参数在收到完整完成事件后才解析并执行。兼容仍返回普通 JSON 的服务。
3. 可填写 Skills 根目录（支持 `~/`）。任务开始时递归发现 `SKILL.md`，将名称和描述提供给模型；模型通过 `skill_read` 按需读取全文。最多 200 个 Skill，单文件最多 128 KiB，不跟随目录符号链接，不允许读取根目录外的文件。Skill 附属脚本可由模型根据指引通过已授权的终端调用。
4. 在右侧底部选择模型、填写任务并点击「发送」。当前会话保留上下文，右上角可新建会话。任务绑定开始时选中的终端，最多 40 轮；工具调用和回复显示在日志中。关闭目标 Tab 后任务停止。点击「停止」会停止后续工具调用；已提交的 shell 命令可用终端 Ctrl+C 中断。

配置保存在 `~/.terminal-use/settings.json`（Windows 使用 `%APPDATA%/.terminal-use/settings.json`），Unix 目录权限 700、文件权限 600。API Key 保存在此本地文件中，输入界面隐藏显示。终端内容与 Skills 会发送给用户配置的模型 Endpoint；运行日志仅保存在本次内存中。当前不包含会话历史持久化和系统钥匙串集成。

在输入框中键入 `@` 可按 Tab 名称或 ID 选择目标。发送前无需手写 ID。

Agent 的每次终端写入（含交互按键和 Ctrl+C）都先通过当前模型的独立请求评估，再在 Agent 上下文区显示目标、原始输入、风险等级和理由。卡片分别展示命令解释和风险依据。默认三个等级均须点击「允许本次执行」才发送。在 Agent 设置中，可针对低、中、高风险分别开启自动放行，开启后匹配该等级的操作直接执行。确认卡片持续等待你决定，打开设置时也会保留。拒绝、取消操作或评估失败均不写入。外部 MCP 写入也需此确认，风险评估使用所选模型（未选择时使用首个配置），待执行输入会发送到该模型的 Endpoint。

## Agent 调试日志

独立风险评估使用 16384-token 输出预算。连接建立超时 30 秒；首个响应头和流空闲阈值：主对话 90 秒、风险评估 120 秒。流空闲按接收到的网络数据重置（含心跳），不以整段生成的总时长计时。取消会关闭当前 HTTP 连接；提前断流、缺少协议结束事件或截断时，不使用部分工具参数授权。官方 `api.deepseek.com` 的 OpenAI 请求显式使用 `thinking.type=disabled` 与 `response_format.type=json_object`，避免短评估的输出预算被默认思考耗尽；其他服务不自动附加 DeepSeek 专用参数。Agent 工具对话保留服务返回的 `reasoning_content` 供后续请求回传。响应若以 `length` / `max_tokens` 结束，会记录 `model.truncated`（含预算与 usage）并拒绝使用部分结果授权，不将其伪装成 HTTP 失败。参考 [DeepSeek 思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)。

Debug 默认向 IDE Run/Debug 控制台输出 `[agent-trace]` 日志；Release 需加 `--dart-define=TERMINAL_USE_TRACE=true`，关闭日志用 `--dart-define=TERMINAL_USE_TRACE=false`。修改此开关需重新运行，热重载不会改变编译参数。项目 Release 脚本也可转发该参数：

```bash
FLUTTER_BIN=/path/to/flutter bash tools/run_macos_release.sh --dart-define=TERMINAL_USE_TRACE=true
```

按 `runId` 找到一次任务，按 `toolCallId` 关联工具与独立风险评估，按 `traceId` 关联同一次 HTTP 请求的 `http.request`、`http.headers`、`http.response`、`http.error`。请求日志包含实际 URL、HTTP 方法、完整 JSON payload（含 system 提示词、messages、tools）；响应日志包含真实状态码、请求 ID、完整响应正文及耗时。`http.sse` 按接收顺序记录原始事件，流式 `http.response` 则记录合并后的完整消息。`tool.start/result/error` 展示工具参数、结果和失败，`risk.assessment/decision` 展示评估与授权，`terminal.write` 表示授权后实际写入的精确字符（回车、Ctrl+C 用 JSON 转义展示），`agent.end` 表示本轮退出。

长事件分片为 `[序号/总片数]`，拼接同一事件各片前缀后的内容即可还原 JSON；不会按长度丢弃 payload。超出 HTTP 响应大小限制或接收失败时，响应可能不完整，以错误事件为准。API Key、鉴权头、URL 查询值和已识别的凭据字段会脱敏，但对话、终端输出、命令与 Skills 正文仍会出现在调试日志中。日志由 IDE/启动命令保存，本应用不另行落盘；分享日志前检查业务内容。

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

省略 `terminal_id` 时保留旧接口语义，固定操作用户首次创建的终端；尚未创建或该终端已关闭时返回错误，不会跟随选中 Tab 或转到其他终端。新接入应始终指定 ID。

`/terminal` 返回指定终端的当前活动 buffer（最多 10000 行），全屏程序显示当前屏幕，不保证包含已离开屏幕的历史。API 不提供单条命令退出码；`exitCode` 是 shell 的退出码。输入与读取均非事务操作，人和 agent 同时输入可能交错。

## 权限

这是本地 shell 工具：agent 和人工终端具有当前用户权限。令牌持有者可执行本地命令，并读取终端中的敏感输出。只给受信任的 agent 连接参数。macOS 为运行任意本地 shell，Debug / Release 已关闭 App Sandbox；这不是 Mac App Store 沙盒应用。

终端组件采用 [xterm](https://pub.dev/packages/xterm) 和 [flutter_pty](https://pub.dev/packages/flutter_pty)。

图标回退字体：[Nerd Fonts Symbols Mono v3.4.0](https://github.com/ryanoasis/nerd-fonts/tree/v3.4.0/patched-fonts/NerdFontsSymbolsOnly)。字体原样打包，许可证见 `assets/fonts/NERD-FONTS-LICENSE.txt`。


## 许可证

本项目原创代码采用 [GNU GPL 第 3 版（仅限该版本，GPL-3.0-only）](LICENSE)。
第三方依赖与字体保留各自的许可证及版权声明，不因本项目采用 GPL 而重新许可。
依赖版本、许可证核对结果与分发注意事项见 [依赖许可证记录](docs/dependency-licenses.md)。

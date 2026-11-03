# Terminal Use

Flutter 桌面终端 + 本地 agent 工作区。左侧为真正的交互式 PTY，右侧运行你已安装的 agent CLI；通过本地 HTTP API 或 MCP，agent 可读取和操作左侧同一终端。

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
# 可选：验证本机已安装的 OpenCode / Codex 实际完成 MCP 工具发现（不调用模型）
flutter test integration_test/terminal_test.dart -d macos --dart-define=TEST_INSTALLED_AGENTS=true
```

本机 Flutter 3.41.5 与 Xcode 的通用架构检查存在兼容问题；若 Release 报 `does not contain architectures "arm64 x86_64"`，Apple Silicon 可在执行上述 Flutter build 后改用：

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release -derivedDataPath build/macos -quiet ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

产物位于 `build/macos/Build/Products/Release/terminal_use_app.app`。

当前在 macOS 开发验证，Linux/Windows 已生成平台工程，但尚未在对应系统验证。默认启动登录 shell（Windows 为 PowerShell），工作目录为用户 HOME。支持 ANSI、中文、交互程序、键盘输入、窗口尺寸同步和 Ctrl+C。内置等宽 Nerd Fonts Symbols 回退字体，支持 agnoster 等 zsh 主题的 Powerline / Nerd Font 图标，无需额外安装系统字体。关闭 app 会向终端和 agent 进程发送终止信号；自行脱离会话的后台进程可能继续运行。

## Agent 接入

右侧提供 **启动 OpenCode** 与 **启动 Codex** 两个按钮。先在本机安装并登录对应 CLI，并安装 Python 3；点击后会自动查找 CLI、检查 MCP 桥接，再启动交互界面。不需要手动编辑 MCP 配置。

- 沿用 CLI 自己的模型、账号与权限设置，首次登录或 CLI 自身要求的确认仍在右侧完成。
- 自动适配 OpenCode V1 / V2 的 MCP 配置结构，通过进程环境注入临时配置。
- Codex 使用本次启动的 `-c` 参数配置 MCP，并显式转发连接环境变量。
- 对支持后台服务的版本使用独立运行模式，确保每个窗口连接本窗口的终端。
- MCP 桥接脚本随 Flutter assets 打包，启动时释放到临时目录，无需保留源码目录；会话结束后清理。
- 启动后会显示 MCP 连接状态；只有 CLI 已读取工具列表后才显示“已连接”。启动本身不会向模型提交任务。
- 不改写用户的全局 CLI 配置，不关闭其工具审批或沙盒。

展开 **高级：其他启动命令** 可输入任意启动命令或复制连接参数。自定义命令启动时注入：

- `TERMINAL_USE_URL`：随机端口，且仅监听 `127.0.0.1`。
- `TERMINAL_USE_TOKEN`：每次 app 启动生成的访问令牌，不写入文件。

下面的手动配置仅针对自定义 CLI。自动按钮无需操作。

CLI 不会仅因获得环境变量就自动调用终端。需要将下面的 MCP 服务配置到 CLI，或告知其使用桥接脚本。MCP 配置文件位置取决于所用 agent，服务配置示例为：

```json
{
  "mcpServers": {
    "terminal_use": {
      "command": "python3",
      "args": ["/Users/sinri/code/personal/TerminalUseApp/tools/terminal_bridge.py", "mcp"]
    }
  }
}
```

请将脚本路径改为实际绝对路径。从 app 右侧启动 agent，让 MCP 子进程继承上述环境变量。MCP 提供 `terminal_read`、`terminal_input`、`terminal_interrupt` 三个工具。

可给 agent 的任务提示：

> 使用 terminal_use MCP 读取共享终端。所有 shell 操作均通过 terminal_input 发送到共享终端，命令末尾追加回车 `\r`。发送后调用 terminal_read 检查结果；命令为异步执行，不要把输入成功当成命令执行成功。执行下一步前先确认终端已空闲。用户也可以操作这个终端。

无需 MCP 的 agent 可以调用脚本：

```sh
python3 /absolute/path/tools/terminal_bridge.py read
python3 /absolute/path/tools/terminal_bridge.py input $'pwd\r'
python3 /absolute/path/tools/terminal_bridge.py interrupt
```

在 app 右侧用下面的命令可先验证读取链路：

```sh
python3 /Users/sinri/code/personal/TerminalUseApp/tools/terminal_bridge.py read
```

## HTTP API

所有请求都必须携带 `Authorization: Bearer <TERMINAL_USE_TOKEN>`。

| 方法 | 路径 | 行为 |
| --- | --- | --- |
| GET | `/terminal` | 返回渲染后的终端 buffer 文本、PID、进程状态、退出码和行列数 |
| POST | `/input` | JSON `{"text":"pwd\r"}`；向 PTY 写入精确输入，最大 64 KiB |
| POST | `/interrupt` | 发送 Ctrl+C |

`/terminal` 返回当前活动 buffer（最多 10000 行），全屏程序显示当前屏幕，不保证包含已离开屏幕的历史。API 不提供单条命令退出码；`exitCode` 是 shell 的退出码。输入与读取均非事务操作，人和 agent 同时输入可能交错。

## 权限

这是本地 shell 工具：agent 和人工终端具有当前用户权限。令牌持有者可执行本地命令，并读取终端中的敏感输出。只给受信任的 agent 连接参数。macOS 为运行任意本地 shell，Debug / Release 已关闭 App Sandbox；这不是 Mac App Store 沙盒应用。

自动配置依据 [OpenCode MCP 文档](https://opencode.ai/docs/mcp-servers/)、[OpenCode V2 MCP 文档](https://dev.opencode.ai/v2/docs/mcp-servers/) 与 [Codex MCP 文档](https://learn.chatgpt.com/docs/extend/mcp?surface=cli)。

终端组件采用 [xterm](https://pub.dev/packages/xterm) 和 [flutter_pty](https://pub.dev/packages/flutter_pty)。

图标回退字体：[Nerd Fonts Symbols Mono v3.4.0](https://github.com/ryanoasis/nerd-fonts/tree/v3.4.0/patched-fonts/NerdFontsSymbolsOnly)。字体原样打包，许可证见 `assets/fonts/NERD-FONTS-LICENSE.txt`。

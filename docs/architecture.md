# 架构与数据流

[文档导航](README.md) · [开发构建](development.md) · [HTTP API](http-api.md) · [诊断](debugging.md)

应用由 Flutter 工作区、本地 PTY、内置 Agent、本地 HTTP 桥接和平台适配层组成。内置 Agent 直接调用终端工具逻辑；外部 MCP 通过 Python stdio 桥接访问同一个工作区，不为每个客户端另建终端。

## 模块职责

以下路径相对项目根目录。

| 模块 | 主要文件 | 职责 |
| --- | --- | --- |
| 应用与工作区 UI | `lib/main.dart` | 启动、设置加载、终端/Agent 编排、平台事件、退出清理 |
| 终端 | `lib/src/terminal_workspace.dart`, `terminal_session.dart` | Tab 与稳定 ID、PTY、终端 buffer、尺寸和进程关闭 |
| Agent | `lib/src/internal_agent.dart` | 对话、Skills 工具、模型循环、目标检查与取消 |
| 会话 | `lib/src/agent_conversations.dart`, `agent_history_view.dart` | 每会话独立 Agent/草稿，Tab 绑定、历史持久化与展示 |
| 模型传输 | `lib/src/api_request.dart`, `model_request.dart`, `model_stream.dart` | 鉴权、HTTP/SSE、超时、取消、响应合并与截断处理 |
| 审批 | `lib/src/terminal_approval.dart` | 独立风险评估、确认卡片、自动放行策略和拒绝 |
| 外部接入 | `lib/src/agent_server.dart`, `tools/terminal_bridge.py` | loopback HTTP 能力接口、Python CLI 与 stdio MCP |
| 本地配置 | `lib/src/settings.dart`, `ssh_credentials.dart` | 模型/SSH/Skills 配置、macOS 钥匙串访问 |
| 界面基础 | `lib/src/mac_controls.dart`, `app_theme.dart` | 控件、焦点、语义与明暗主题 |
| About | `lib/src/about_view.dart` | 版本、项目、作者和许可证入口 |
| macOS 适配 | `macos/Runner/AppDelegate.swift`, `MainFlutterWindow.swift` | 原生菜单、MethodChannel、退出、钥匙串、版本元数据 |

## 终端和目标稳定性

`TerminalWorkspace` 分配本次运行中的稳定终端 ID。每个 Tab 持有独立 `TerminalSession`，后者连接 PTY 与 xterm buffer。关闭 Tab 后 ID 不复用；旧 API 固定指向首次创建的终端，不隐式跟随当前选择。

内置 Agent 在任务开始时绑定目标 ID，工具调用前重新检查目标仍存在。会话与 Tab 可以一对一绑定，但可见会话切换与运行任务的归属是分开的：切换 UI 不会把在途响应或审批重定向到别的会话。

## 写入与审批路径

内置 Agent 的终端写入先进入 `TerminalApproval`，使用独立模型请求评估，再按用户确认或该风险等级的自动放行策略决定是否提交到 PTY。模型响应完整性、取消和目标有效性也是写入前置条件。

外部客户端通过 Python MCP → loopback HTTP → `Workspace` 外部输入处理进入审批，再写入目标终端。人工在终端中直接输入使用正常终端输入路径，不需要 Agent 审批。

独立评估仍依赖用户配置的模型，不提供系统沙盒。进程具有用户权限；人和 Agent 可以同时输入，读取与写入没有事务保证。接口细节见 [HTTP API](http-api.md)。

## 模型和 Skills

服务配置确定协议、端点、认证与模型。请求层处理 HTTP 与超时，流解析层合并 SSE；Agent 在完整工具参数可用后才调用工具。风险请求和主对话的预算、超时与诊断事件见 [诊断说明](debugging.md)。

Skills 从用户配置的根目录发现，模型获得索引后按需读取正文。根目录读取边界不意味着终端命令也受该目录限制；模型请求和已授权终端脚本的权限边界需分别理解。

## 持久化与凭据

模型 API Key 与服务配置在本地 `settings.json`；macOS SSH 密码在系统钥匙串。会话上下文、工具/审批记录与草稿保存于 `agent-history.json`，终端 Tab 和绑定不跨 App 重启恢复。历史读取失败时保留文件并暂停覆盖，未完成任务不会自动恢复执行。

具体路径和用户数据处理见 [使用指南](user-guide.md#模型skills-与执行审批)。历史文件含业务数据，不作为开发示例或发行资产。诊断日志默认只在 Debug 开启，见 [诊断说明](debugging.md)。

## 原生菜单与退出

macOS 菜单经 MethodChannel 路由到 Flutter 工作区，复制/粘贴/全选根据焦点分派。版本来自 Bundle，许可证通过 Flutter LicenseRegistry 汇集项目、字体及依赖声明。

macOS 关窗和 ⌘Q 共用退出流程：保持 Flutter 引擎存活，先停止内部 Agent，并行关闭桥接与各 PTY，再退出进程。正常清理完成后立即退出；Dart 暂停或失联时，原生端在约 2 秒后结束等待，此时不能保证所有清理完成。`nohup` 或自行脱离会话的进程可以继续运行。

## 验证和演进

测试入口见 [开发指南](development.md)，按日期记录的已验证范围见 [实施状态](implementation-plan.md)。产品目标见 [愿景](vision.md)，桌面交互规范见 [UI 文档](ui-design.md)，签名、公证及发行步骤见 [发行指南](releasing.md)。

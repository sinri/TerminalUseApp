# 本地 HTTP API

[文档导航](README.md) · [MCP 接入](mcp.md) · [架构](architecture.md)

本文面向实现自定义终端客户端的开发者。服务只监听 `127.0.0.1` 的随机端口，随 App 退出关闭；端口和令牌每次启动重新生成，不是远程公开服务。

所有请求都必须携带 `Authorization: Bearer <TERMINAL_USE_TOKEN>`。

| 方法 | 路径 | 行为 |
| --- | --- | --- |
| GET | `/terminals` | 枚举当前 Tab 的 ID、名称和运行状态 |
| GET | `/terminal?terminal_id=terminal-1` | 返回渲染后的终端 buffer 文本、PID、进程状态、退出码和行列数 |
| POST | `/input?terminal_id=terminal-1` | JSON `{"text":"pwd\r"}`；向 PTY 写入精确输入，最大 64 KiB |
| POST | `/interrupt?terminal_id=terminal-1` | 发送 Ctrl+C |

省略 `terminal_id` 时保留旧接口语义，固定操作用户首次创建的终端；尚未创建或该终端已关闭时返回错误，不会跟随选中 Tab 或转到其他终端。新接入应始终指定 ID。

`/terminal` 返回指定终端的当前活动 buffer（最多 10000 行），全屏程序显示当前屏幕，不保证包含已离开屏幕的历史。API 不提供单条命令退出码；`exitCode` 是 shell 的退出码。输入与读取均非事务操作，人和 agent 同时输入可能交错。

## 错误响应与执行边界

响应为 JSON。缺少或错误鉴权返回 401；未知接口返回 404；输入格式错误返回 400；目标已关闭、执行被拒绝或其他状态冲突返回 409，错误信息位于 `error` 字段。`/input` 对 JSON 请求体执行 64 KiB 限制，不能把它理解为 64 KiB 文本外加无限 JSON 开销。

写入和中断经过 App 中的独立风险评估与审批，HTTP 请求可能在用户决定前保持等待。输入成功只表示已提交到 PTY，不表示命令执行完成。客户端应读取终端确认结果，避免重试导致重复命令。

令牌是当前会话的终端访问能力，不要发布到日志或转发至网络。风险评估所需输入会发送至用户配置的模型服务，见 [使用指南](user-guide.md)。

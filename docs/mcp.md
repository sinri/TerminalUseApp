# 外部 Agent / MCP 接入

[文档导航](README.md) · [使用指南](user-guide.md) · [HTTP API](http-api.md)

App 内置 Agent 可直接使用终端，无需额外启动 MCP。本文用于连接独立的 MCP 客户端。

## 建立连接

1. 启动 App，并创建要操作的终端。
2. 在 Agent 设置中复制本次启动的 MCP 连接参数。复制内容为 `TERMINAL_USE_URL` 和 `TERMINAL_USE_TOKEN`。
3. 准备本地 [桥接脚本](../tools/terminal_bridge.py)（可从对应版本源码包取得），在客户端添加 stdio MCP 服务，命令为 `python3`，参数为桥接脚本绝对路径及 `mcp`；将 URL 和令牌放入该 MCP 进程的环境变量。客户端需要能运行 Python 3。
4. 调用 `terminal_list` 确认连接和目标 ID。App 重启后重新复制参数；退出 App 后连接失效。

不同客户端的配置外层格式可能不同，以下仅展示常见的服务定义。占位符必须替换为当前 App 中复制的值：

```json
{
  "mcpServers": {
    "terminal_use": {
      "command": "python3",
      "args": ["/absolute/path/terminal_bridge.py", "mcp"],
      "env": {
        "TERMINAL_USE_URL": "http://127.0.0.1:<当前端口>",
        "TERMINAL_USE_TOKEN": "<当前启动的令牌>"
      }
    }
  }
}
```

从源码运行时，桥接脚本位于项目的 `tools/terminal_bridge.py`。发行包用户需另行保存该脚本并使用其绝对路径；App 的复制按钮仅提供 URL 和令牌，不会下载脚本或提供脚本路径。无需安装 Flutter 或额外 Python 包。

## 工具

| 工具 | 参数 | 用途 |
| --- | --- | --- |
| `terminal_list` | 无 | 枚举终端，获取稳定 ID |
| `terminal_read` | `terminal_id` | 读取当前屏幕和可用滚动内容 |
| `terminal_run` | `terminal_id`, `command` | 提交 shell 命令并自动发送回车 |
| `terminal_input` | `terminal_id`, `text` | 向交互程序发送精确按键 |
| `terminal_interrupt` | `terminal_id` | 发送 Ctrl+C |

例如先从 `terminal_list` 取得 `terminal-1`，再调用：

```json
{"terminal_id":"terminal-1","command":"pwd"}
```

普通 shell 命令使用 `terminal_run`，不要自行追加回车；交互输入才使用 `terminal_input`。输入成功不等于命令完成，随后调用 `terminal_read` 确认结果。终端文本可能属于运行中的程序或部分输入，操作前先读取，不要覆盖人工正在输入的内容。

始终传入 `terminal_id`。切换 UI 的活动 Tab 不会改变既定目标，关闭目标后原 ID 失效，不会转到其他终端。不传 ID 的兼容行为见 [HTTP API](http-api.md)。

## 审批与权限

外部 MCP 的写入和中断也经过 App 风险评估与审批，使用当前所选模型，未选择时使用首个配置。未完成模型配置或评估失败时，写入不能正常获准；等待用户审批期间客户端请求可能保持等待，不要重复发送命令。

令牌允许读取终端中的敏感输出并请求写入；只交给受信任的客户端，不能贴到公开 Issue。风险评估会把待执行输入发送到已配置模型服务。

## 排障

检查 App 是否仍运行、脚本路径和 Python 3 是否可用、连接参数是否来自当前启动、目标 ID 是否仍存在，以及 App 是否有待决定的审批。协议端点和错误码见 [HTTP API](http-api.md)，业务数据与日志注意事项见 [使用指南](user-guide.md#权限与数据)。

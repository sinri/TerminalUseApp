# 愿景实施计划与当前状态

[文档导航](README.md)

以 [愿景](vision.md) 为目标，应用内提供内置 Agent，独立客户端可连接 Terminal MCP。
以下状态截至 2026-11-09，当前发行版为 `1.0.0+1`。

## 已实现

1. 稳定 ID 的多终端工作区，支持纵向 Tab、新建、重命名、关闭、复制粘贴；MCP 按 ID 操作。
2. SSH 入口使用系统 OpenSSH，支持用户、端口、密钥和密码认证、心跳与主机指纹确认。macOS 密码保存到系统钥匙串；其他平台在终端交互输入。
3. 多个 LLM 服务与模型，支持 OpenAI-compatible Chat Completions 和 Anthropic Messages；主对话和风险评估使用 SSE，兼容普通 JSON 响应。
4. Skills 发现和按需读取，外部 Python stdio MCP，共享同一终端工具契约。
5. 独立风险评估与逐次确认，可按风险等级配置自动放行；评估失败或流截断时不执行。
6. Agent 会话历史、上下文、草稿、搜索及 Tab 一对一绑定。历史保存到本地 `agent-history.json`，绑定不跨 App 重启恢复。
7. 原生菜单、中文输入、可调整分栏、深浅主题、About 项目和许可证入口。
8. 版本递增、Developer ID 签名、公证和 DMG 打包，首次发行已上传 GitHub Release。

## 关键边界

- Terminal ID 与 Tab 生命周期一致。旧 API 固定首次创建的终端，不跟随活动 Tab。
- LLM API Key 保存于本地配置文件，Unix 目录权限 700、文件权限 600；不是加密密钥存储。SSH 密码在 macOS 使用系统钥匙串。
- 终端文本、任务和 Skills 会发送到用户选择的模型服务。调试日志可能包含业务内容；Release 默认关闭追踪。
- Agent 使用当前用户权限，风险评估不是沙盒。切换 Tab 不改变运行中任务目标；关闭目标 Tab 会停止后续操作。
- 每轮任务最多 40 轮工具循环。停止任务取消在途模型请求，不保证撤销已执行的 shell 命令。
- Skills 正文读取受根目录约束；附属脚本可通过已授权终端执行。

## 验证记录

- `flutter analyze`：无问题。
- `flutter test`：57 项通过（首次发行构建时）。覆盖终端路由、模型协议/SSE、审批、会话历史、SSH 凭据和桌面控件等。
- 发版工具 Python 测试：7 项通过；覆盖版本递增、脏工作区/错误标签、签名配置、公证拒绝和产物篡改拦截。
- macOS Debug / Release 构建成功。`1.0.0+1` arm64 的 App 和 DMG 均通过签名、公证、票据装订及 Gatekeeper 检查。
- 早期 macOS 桌面集成测试曾验证真实 PTY、Python MCP、中文输入、菜单与风险确认；此次发行流程未重新运行该集成测试，不能把历史结果当作当前版本完整端到端验收。

Linux / Windows 保留平台工程，未在对应系统实机验证。不提供通用双架构包。
真实 SSH 服务器、付费模型服务、其他 Mac 与最低系统版本的完整兼容性仍需实机验证。
发行流程见 [发行指南](releasing.md)，详细操作说明以 [使用指南](user-guide.md) 为准；开发与模块关系从 [文档导航](README.md) 进入。

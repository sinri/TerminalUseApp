# 愿景实施计划

以 docs/vision.md 为目标，应用内只提供内置 Agent，独立客户端可连接 Terminal MCP。

1. 建立有稳定 ID 的多终端工作区；纵向 Tab、新建、重命名、关闭、复制粘贴；MCP 枚举并按 ID 操作。
2. 本地保存 SSH 入口，使用系统 OpenSSH 与参数数组启动，支持用户、端口、密钥与交互密码，默认心跳。
3. 本地保存多个 LLM 配置，提供 OpenAI-compatible Chat Completions 和 Anthropic Messages 协议、Bearer/API Key/无认证；内部 Agent 通过与 MCP 相同的工具契约运行，提供停止、执行上限与操作日志。
4. Skills 根目录配置、发现 SKILL.md、按需读取；提供本地 MCP 连接参数。
5. 单元测试验证定向路由、配置、协议与工具循环，运行静态分析、现有测试及桌面集成验证。

## 设计决策

- SSH 密码不保存，直接在 SSH 终端输入；保留 OpenSSH 主机指纹确认与系统 SSH 配置。密钥默认 ~/.ssh/id_rsa，可指定其他路径。
- Terminal ID 与 Tab 生命周期一致，关闭后返回错误；旧 API 保留固定首个终端兼容语义，绝不隐式跟随活动 Tab。新工具通过 terminal_id 定向。
- LLM API Key 可本地保存，配置目录仅当前用户可访问；界面隐藏密钥。后续可扩展系统钥匙串。终端文本与 Skills 会发送至用户选定的 Endpoint。
- 内部 Agent 直接复用本地工具契约，无需额外启动 Python MCP 子进程。工具每次执行前校验绑定终端，用户切换 Tab 不改变当前任务目标。写入操作由用户在任务开始时授权，运行中可停止。
- Skills 采用根目录下递归发现 SKILL.md、展示描述、按需加载全文；不执行安装脚本，不隐式读取根目录外文件。

## 验收记录

已完成上述五个阶段。

- `flutter analyze`：无问题。
- `flutter test`：11 项通过。覆盖鉴权、输入边界、按 ID 路由、SSH 参数、配置权限与连续保存、Skills 路径边界、两种模型协议工具循环、停止 Agent 或关闭绑定 Tab 时取消在途请求。
- `flutter test integration_test/terminal_test.dart -d macos`：3 项通过。覆盖桌面界面、内置 Agent 任务面板、设置表单、720×640 布局、Python MCP → HTTP → 真实 PTY、Tab 切换隔离、关闭前台子进程、保留 nohup 后台进程、关闭 ID 后拒绝写入。
- macOS Debug 构建成功。标准 Release 命令触发原有 Flutter 通用架构检查问题，使用 README 已有的 `xcodebuild ... ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build` 后 Release 构建成功。
- macOS 原生退出通过 MethodChannel 等待本地服务、Agent、PTY 与临时文件清理；Windows 关闭使用 `taskkill /T`，Unix 使用 PTY 范围挂断与 shell 退出兜底。

尚未使用真实 SSH 服务器凭证或付费 LLM Endpoint 做端到端运行；模型协议通过本地模拟服务器验证。Linux / Windows 工程保留，未在对应系统实机验证。当前内部 Agent 使用非流式响应、内存日志与 40 轮上限；Skills 支持 SKILL.md 发现和正文读取，附属文件/脚本由已授权终端按指引访问。

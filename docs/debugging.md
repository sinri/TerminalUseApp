# 模型请求与日志诊断

[文档导航](README.md) · [开发构建](development.md) · [用户常见问题](user-guide.md#常见问题)

本文面向定位模型协议、风险评估和终端工具调用问题的开发者。日志含业务文本，不能直接作为公开 Issue 附件。

## 请求预算与流处理

独立风险评估使用 16384-token 输出预算。连接建立超时 30 秒；首个响应头和流空闲阈值：主对话 90 秒、风险评估 120 秒。流空闲按接收到的网络数据重置（含心跳），不以整段生成的总时长计时。取消会关闭当前 HTTP 连接；提前断流、缺少协议结束事件或截断时，不使用部分工具参数授权。官方 `api.deepseek.com` 的 OpenAI 请求显式使用 `thinking.type=disabled` 与 `response_format.type=json_object`，避免短评估的输出预算被默认思考耗尽；其他服务不自动附加 DeepSeek 专用参数。Agent 工具对话保留服务返回的 `reasoning_content` 供后续请求回传。响应若以 `length` / `max_tokens` 结束，会记录 `model.truncated`（含预算与 usage）并拒绝使用部分结果授权，不将其伪装成 HTTP 失败。参考 [DeepSeek 思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)。

## 启用与关联日志

Debug 默认向 IDE Run/Debug 控制台输出 `[agent-trace]` 日志；Release 需加 `--dart-define=TERMINAL_USE_TRACE=true`，关闭日志用 `--dart-define=TERMINAL_USE_TRACE=false`。修改此开关需重新运行，热重载不会改变编译参数。项目 Release 脚本也可转发该参数：

```bash
FLUTTER_BIN=/path/to/flutter bash tools/run_macos_release.sh --dart-define=TERMINAL_USE_TRACE=true
```

按 `runId` 找到一次任务，按 `toolCallId` 关联工具与独立风险评估，按 `traceId` 关联同一次 HTTP 请求的 `http.request`、`http.headers`、`http.response`、`http.error`。请求日志包含实际 URL、HTTP 方法、完整 JSON payload（含 system 提示词、messages、tools）；响应日志包含真实状态码、请求 ID、完整响应正文及耗时。`http.sse` 按接收顺序记录原始事件，流式 `http.response` 则记录合并后的完整消息。`tool.start/result/error` 展示工具参数、结果和失败，`risk.assessment/decision` 展示评估与授权，`terminal.write` 表示授权后实际写入的精确字符（回车、Ctrl+C 用 JSON 转义展示），`agent.end` 表示本轮退出。

长事件分片为 `[序号/总片数]`，拼接同一事件各片前缀后的内容即可还原 JSON；不会按长度丢弃 payload。超出 HTTP 响应大小限制或接收失败时，响应可能不完整，以错误事件为准。API Key、鉴权头、URL 查询值和已识别的凭据字段会脱敏，但对话、终端输出、命令与 Skills 正文仍会出现在调试日志中。日志由 IDE/启动命令保存，本应用不另行落盘；分享日志前检查业务内容。

## 安全提供诊断材料

优先用最小测试任务重现，附版本、协议、HTTP 状态和错误事件。需要完整日志时在本机检查并删除 API Key、MCP 令牌、对话、终端输出、Skills 正文和私有地址；自动脱敏不保证隐藏业务内容。
示例请求见 [风险评估请求样例](examples/risk-assessment-request.json)，样例不含真实凭据。

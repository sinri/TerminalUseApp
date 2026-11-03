# Vision of Terminal Use App

## Terminal

提供常规命令行终端交互体验。保证 ZSH 等命令行下 Powerline 字符显示正常。

允许用户使用复制粘贴操作。

左侧设置纵向 tab 列，可切换多个命令行终端。

## Terminal MCP

对本地服务提供MCP，允许使用 MCP 的 Agent 获取命令行终端清单并操作指定命令行终端（在某一个特定的 Tab 页下）。

在 App 关闭后，MCP 服务停止。

## Terminal Use

### Outside Me

外部 Agent 工具，如 Codex 和 OpenCode 等，可以便捷挂载 Terminal MCP，在本 App 运行时进行 Terminal Use 操作。

需要在 App 内给出使用步骤指导。

### Inside Me

在内部集成一个 Agent，可直接连接 LLM 运行命令行运维工作辅助 Agent。

通过配置页面设定 LLM 协议、Endpoint、认证方式和 ApiKey 等，配置存于本地。可存放多个 LLM 配置，供 Agent 运行时选用。

此 Agent 默认集成 Terminal MCP。

此 Agent 默认支持 Skill 体系，允许用户选择 skill 存放根目录以引用。
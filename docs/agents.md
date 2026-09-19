# 智能体接入

[返回项目首页](../README.md)

在 **设置 → 智能体** 中选择默认智能体、添加或编辑连接配置。气泡标题手动切换智能体时，会同步更新并保存设置中的默认值，之后新开的气泡沿用上次选择；已有对话切换时另起一段对话，原记录保留。回顾旧记录不会改变默认值。旧版本的对话继续归属 Codex。

| 智能体 | 接入方式 |
| --- | --- |
| Codex | 原有 app-server；自动发现桌面应用 / CLI，可指定命令路径和模型 |
| Claude Code | 本机 `claude` 的非交互 JSON 输出；复用 CLI 登录 |
| OpenCode | 本机 `opencode run --format json`；复用 CLI 配置 |
| Pi Agent | 本机 `pi --print --mode json`；复用 CLI 配置 |
| OpenClaw | Gateway 的 OpenAI 兼容接口，默认基础地址 `http://127.0.0.1:18789/v1`、智能体 `openclaw/default` |
| CodeBuddy | `codebuddy` / `cbc` 非交互 JSON 输出；不会将 IDE 启动器 `buddycn` 当作 Agent |
| Cursor | `cursor-agent` / `agent` 的 Ask 模式；需要安装 Cursor CLI，桌面应用本身不等于 CLI |
| Kimi | `kimi --quiet --plan`，复用 CLI 登录 |
| Qoder | `qoder` / `qodercli` 非交互文本输出 |
| Hermes | 官方 Agent API Server，默认 `http://127.0.0.1:8642/v1`，标识 `hermes-agent`；需启用 API Server 并配置 Key |
| Smartwork | D-Chat 内置 Agent 原生协议，默认 `http://127.0.0.1:8764`；复用客户端模型和登录 |
| WorkBuddy | 官方本地助理 Open API；需填入具有 localassistant.readable / invokable 权限的 Access Token，并保持电脑端在线 |
| 千问办公 | 可配置办公 Agent 包装命令 / 兼容服务；尚未确认公开的问答协议，不等同于普通千问模型接口 |
| DeepSeek Harness / 自定义 | 配置兼容 HTTP 服务，或通过自定义命令包装专有协议 |

打开设置自动检测常见命令路径（包括 Homebrew、NVM、用户 bin），并列出当前用户可见的本机监听端口。端口列表仅用于定位服务，不推断它是哪个智能体，也不发送测试提问；已配置的 localhost HTTP 服务仅以匿名 `GET /models` 检查响应。Smartwork 另外匿名检查 `/api/agent/health` 的名称与协议标识，本机服务已验证；未知服务需手动填写地址与协议。扫描不会读取认证信息或发起模型调用。

HTTP 配置使用包含 `/v1` 的基础地址、模型/智能体标识，以及可选的 API Key / Bearer Token。认证信息存于 macOS 钥匙串，不写入对话记录。OpenClaw 需要先启用 Gateway 的 `chatCompletions` 端点。远端工具权限由服务端控制。

自定义命令的参数为 JSON 字符串数组，例如 `["--print"]`。Mirror 直接启动可执行文件，不经过 shell；stdin 传入阅读助手说明和 JSON 编码的完整对话，stdout 返回 UTF-8 回答，stderr 用于命令自身诊断。每轮重新启动，包装脚本负责对接专有协议、认证与退出信号。不要把密钥放入参数。

Codex 沿用服务端会话；其他连接每轮携带 Mirror 保存的对话上下文，避免借用 CLI 的“最近会话”。配置快照保存在对应的气泡记忆中，之后修改默认服务不会改变旧记录的去向。Claude / CodeBuddy / Qoder / Pi 禁用内置工具，OpenCode 使用专用阅读配置禁止工具，Cursor 使用 Ask 模式、Kimi 使用 Plan 模式；这些 CLI 选项需要较新版本。未安装或版本不支持时，气泡显示错误并保留问题供重试。

验证：`bash scripts/test-agents.sh` 使用本地假 CLI 与 HTTP 服务覆盖流式输出、Unicode、多轮、取消、错误、重定向阻止、配置持久化和历史归属；不会调用真实模型。

协议依据：[Claude Code](https://code.claude.com/docs/en/headless)、[OpenCode CLI](https://opencode.ai/docs/cli/)、[Pi JSON](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/json.md)、[OpenClaw Gateway](https://docs.openclaw.ai/gateway/openai-http-api)。新增协议依据：[CodeBuddy](https://www.codebuddy.ai/docs/cli/cli-reference)、[Cursor](https://prod.cursor.com/docs/cli/using)、[Kimi](https://moonshotai.github.io/kimi-cli/en/reference/kimi-command.html)、[Qoder](https://docs.qoder.com/cli/cli-reference)、[Hermes Agent API](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server)、[WorkBuddy Open API](https://open.workbuddy.cn/docs/openapi)。Smartwork 对照本机客户端打包的 `smartwork-agent-turns-v1` 实现，并完成匿名健康检查；其余新接口通过模拟服务验证，未发送真实模型问题。

WorkBuddy 使用共享的本地助理消息通道，返回本次消息后的首条文字回复；请避免同时从其他入口向它提问。Mirror 检测到其他用户消息时停止归属这次回复，权限确认需在 WorkBuddy 中处理。停止等待或删除本机记录不会终止 WorkBuddy 中已接收的任务。Access Token 到期后需要重新授权并更新；Mirror 不内置第三方应用的 OAuth 客户端密钥。

千问办公公开开发文档目前展示管理接口，故预设标为待配置；只有接好办公 Agent 桥接后才能使用。不会将 `qwen` 模型 CLI 或阿里云普通模型 API 自动认作千问办公。



## 模型与思考深度

气泡顶部的调节按钮可设置模型 ID 和思考深度，并同步保存到设置。留空表示沿用智能体默认配置。对已有讨论应用新配置会开启新对话，保留旧记录与未发送草稿。

- Codex、Claude Code、Pi 支持显式思考深度；可用级别取决于模型和本机 CLI 版本。
- Smartwork 支持模型 ID（或 `provider::model`），思考深度由客户端管理。
- 其他原生 CLI 与兼容 HTTP 接入支持模型配置；WorkBuddy、自定义命令由对应客户端或包装脚本管理。
- 暂未确认深度协议的接入不会发送推测参数。Pi 参数依据[官方 CLI 文档](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent#model-options)。

打开气泡中的配置区会自动查询可用模型，也可点击刷新：Codex 使用独立的 `model/list` 连接，读取模型对应的思考深度；Smartwork 使用 `/api/agent/models`；兼容 HTTP 服务使用 `/models`。查询仅获取元数据，HTTP 查询使用已配置的认证信息，不发送提问。Smartwork 当前列表未返回思考深度，仍由客户端管理；其他未接入查询协议的 CLI 保留手动模型配置。查询失败不会覆盖已保存的选择。


## 引用到已有 Codex 会话

选中文字后，右键选择「引用到 Codex 会话…」，或点击提问气泡引用区的会话按钮。Mirror 会展示本机 Codex 的会话列表，让你选择目标并预填引用草稿。该入口独立于气泡的默认智能体。运行时机制、草稿替换行为、支持范围与验证方法见[会话引用说明](codex-thread-reference.md)。

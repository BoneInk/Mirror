# 引用到已有 Codex 会话

## 使用

1. 在 Markdown 编辑器、预览或阅读模式中选中文字，右键选择「引用到 Codex 会话…」。也可从提问气泡引用区的会话按钮进入。
2. 在 Mirror 窗口中查看引用原文、来源路径和位置，以及本机未归档 Codex 会话的标题、内容预览、目录和更新日期。可搜索已加载会话、刷新或加载更多。
3. 选中目标，点击「在 Mirror 续聊」，查看原会话历史与引用草稿。退出 Codex 桌面（⌘Q），停止其他客户端中的同一会话后，在 Mirror 点击「发送」。后续消息保存在原会话中。
4. 也可选择「在 Codex 打开」，在桌面中核对并发送。**此入口会替换 Codex 原有的未发送草稿，请先保存。**

未保存文档用文档标题标识来源；预览选区使用已有的来源位置描述。引用保持多行文本，统一 CRLF/CR 为 LF，并以 Markdown 引用块包裹。不上传整个文件，不截断引用。URL 编码后超过 64 KB 时拒绝投递，提示缩小选区。

列表失败可刷新，投递失败可重试，引用快照保持不变。成功提示只代表系统接受了打开请求；Mirror 没有桌面输入框的接收回执，不声称已经发送。

## 运行时集成与边界

- Mirror 使用自己的 `CodexAppServer` stdio 连接启动本机 `codex app-server --listen stdio://`。优先通过 `com.openai.codex` 发现桌面应用的内置可执行文件（应用名称可以是 ChatGPT），其次查找 CLI；不依赖开发任务的 MCP 工具。
- `initialize` 后调用 `thread/list`，按 `updated_at` 排序，指定 `cli`、`vscode`、`appServer`、`exec` 来源，排除临时会话与归档会话。跨目录显示，不包含其他机器或云端 ChatGPT 会话。查询沿用本进程的 `CODEX_HOME`；如自定义此变量，应让 Mirror 和 Codex 使用同一个目录。
- 投递前用 `thread/read`（`includeTurns: false`）再次校验所选 ID，然后通过 `NSWorkspace` 打开 `codex://threads/<UUID>?prompt=<URL 编码的引用>`。不会在目标不可用时回退到新会话。
- 列表连接不反映另一个 app-server 进程的实时运行状态，因此 UI 不把 `notLoaded` 当作“空闲”。Mirror 续聊在发送前检查 Codex 桌面是否退出，再以原 ID 调用 `thread/resume`、`turn/start`；不创建替代会话、不重放历史。
- 只有 CLI 时可读取本地列表，但填入草稿需要 Codex 桌面应用。旧版桌面不保证支持现有会话的 prompt 深链接；若只打开会话而没有草稿，需更新桌面应用。
- 原有气泡阅读助手仍使用临时会话与自己的本机记忆，和已有会话引用相互独立。

公开列表协议依据：[OpenAI App Server 文档](https://learn.chatgpt.com/docs/app-server#list-threads-with-pagination--filters)。现有会话的草稿深链接依据本机 Codex 桌面 `26.915.31029` 的实际实现核对：路由解析 `localConversation` 的 `prompt`，导航传递 `prefillPrompt`，输入框消费该值并调用 `setPromptText`。这是已核对的桌面行为，不是具有接收回执的公开发送 API。内置 CLI 为 `0.155.0-alpha.9`；独立 CLI `0.154.0` 也提供列表协议。

## Mirror 续聊边界

- 通过 `thread/read` 加载历史，显示文字、附件占位和工具摘要，暂不完整渲染桌面卡片。
- 使用只读文件沙箱与 `approvalPolicy: never`，保留原模型及工作目录。恢复时会覆盖沙箱与批准策略，回到桌面执行修改前应检查权限设置。桌面专属工具、交互批准暂不支持。
- Codex 桌面重新启动时 Mirror 断开，要求退出桌面后刷新历史。会话锁防止多个 Mirror 进程同时续聊；其他 CLI 客户端需要自行停止，系统进程检测不是跨客户端原子锁。
- 发送超时或断线后禁止直接重发，需刷新历史核对；草稿保留，不自动重试。
- 生成期间关闭窗口会在后台继续，重新选择同一会话可打开。需要终止时先点击「停止生成」。闲置关闭时会提示是否丢弃未发送草稿。

## 验证

```bash
swift build -c debug
bash scripts/test-codex-thread-picker.sh
bash scripts/test-codex-existing-thread.sh
bash scripts/test-codex-thread-picker.sh --live
bash scripts/test-codex-reference.sh
bash scripts/build-app.sh debug
```

默认测试用模拟请求与 URL 接收器，覆盖加载、空列表、畸形响应、分页去重、同名会话、搜索、目标校验、Unicode/多行/来源、失败重试、重复点击、超长引用和窗口关闭竞态。`--live` 只验证本机实际 app-server 的列表，不生成模型内容、不修改会话。

续聊模拟测试覆盖：桌面未退出拦截、历史加载、同 ID 多轮、引用仅首次、流式输出、停止、断线后禁止自动重发和关闭失效。真实模型发送尚需退出 Codex 后人工验收：在 Mirror 连续发送两轮，关闭续聊窗口，再打开 Codex 核对原会话历史。

本次本机验证：实际读取 40 条非临时会话；在构建的 Mirror 应用中通过 README 选区右键打开选择窗口，核对来源行号、真实列表、搜索与目标选择；原有引用回归通过。自动化工具禁止读取或操作 Codex 桌面自身，因此最终输入框接收及发送未做自动端到端验收。

人工端到端验收：使用一个草稿可替换的已有本地会话，按上面的 1–4 步操作，核对目标 ID、来源、中文、多行内容，以及 Codex 中的实际草稿；发送后检查会话消息。不要用系统 `open` 返回成功替代这一检查。

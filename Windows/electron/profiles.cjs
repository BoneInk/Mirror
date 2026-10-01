const nativeCommands = {
  codex: ["codex"],
  claude: ["claude"],
  codebuddy: ["codebuddy", "cbc"],
  cursor: ["cursor-agent", "agent"],
  kimi: ["kimi"],
  qoder: ["qoder", "qodercli"],
  opencode: ["opencode"],
  pi: ["pi"],
};
const presets = [
  ...Object.keys(nativeCommands).map((kind) => ({
    id: kind,
    kind,
    name: {
      codex: "Codex",
      claude: "Claude Code",
      codebuddy: "CodeBuddy",
      cursor: "Cursor",
      kimi: "Kimi",
      qoder: "Qoder",
      opencode: "OpenCode",
      pi: "Pi Agent",
    }[kind],
    connection: "native",
    executable: "",
    model: "",
    effort: "",
  })),
  {
    id: "smartwork",
    kind: "smartwork",
    name: "Smartwork",
    connection: "smartwork",
    endpoint: "http://127.0.0.1:8764",
    model: "",
  },
  {
    id: "workbuddy",
    kind: "workbuddy",
    name: "WorkBuddy",
    connection: "workbuddy",
    endpoint: "https://www.workbuddy.cn/openapi/v2",
    model: "",
  },
  {
    id: "hermes",
    kind: "hermes",
    name: "Hermes",
    connection: "http",
    endpoint: "http://127.0.0.1:8642/v1",
    model: "hermes-agent",
  },
  {
    id: "openclaw",
    kind: "openclaw",
    name: "OpenClaw",
    connection: "http",
    endpoint: "http://127.0.0.1:18789/v1",
    model: "openclaw/default",
  },
  {
    id: "qwenwork",
    kind: "qwenwork",
    name: "千问办公",
    connection: "command",
    executable: "",
    arguments: "[]",
    model: "",
  },
  {
    id: "deepseekHarness",
    kind: "deepseekHarness",
    name: "DeepSeek Harness",
    connection: "http",
    endpoint: "",
    model: "",
  },
  {
    id: "http",
    kind: "http",
    name: "兼容 HTTP 服务",
    connection: "http",
    endpoint: "http://127.0.0.1:18789/v1",
    model: "",
  },
  {
    id: "custom",
    kind: "custom",
    name: "自定义命令",
    connection: "command",
    executable: "",
    arguments: "[]",
    model: "",
  },
];
const connection = (profile) =>
  profile.connection ||
  (profile.kind === "http"
    ? "http"
    : profile.kind === "custom"
      ? "command"
      : "native");
const effortOptions = (kind) =>
  kind === "codex"
    ? ["", "none", "minimal", "low", "medium", "high", "xhigh"]
    : kind === "claude"
      ? ["", "low", "medium", "high", "xhigh", "max"]
      : kind === "pi"
        ? ["", "off", "minimal", "low", "medium", "high", "xhigh", "max"]
        : [""];
module.exports = { nativeCommands, presets, connection, effortOptions };

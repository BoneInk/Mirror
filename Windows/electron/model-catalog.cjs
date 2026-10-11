const { spawn } = require("node:child_process");
const { StringDecoder } = require("node:string_decoder");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { resolveCommand } = require("./agents.cjs");
const { nativeCommands } = require("./profiles.cjs");
const supported = ["claude", "codebuddy", "cursor", "opencode", "pi", "kimi", "qoder"];
const failure = () => Error("模型列表无法识别，请检查 CLI 版本与登录；仍可手动填写。");
function unique(rows) {
  const seen = new Set();
  return rows.filter((r) => r.id && !seen.has(r.id) && seen.add(r.id));
}
function option(id, name = id, isDefault = false, efforts) {
  return { id, name, isDefault, ...(efforts !== undefined ? { efforts } : {}) };
}
function parseACP(result, kind) {
  const config = result.configOptions?.find((c) =>
    (c.category === "model" || c.id === "model") && c.type === "select");
  const rows = config?.options?.flatMap((r) => r.options || [r]) || result.models?.availableModels;
  const current = config?.currentValue || result.models?.currentModelId;
  if (!Array.isArray(rows)) throw Error("此 CLI 版本未返回模型列表，可更新 CLI 或手动填写。");
  const cliID = (id) => kind === "kimi" ? id.replace(/,thinking$/, "") : id;
  return unique(rows.flatMap((r) => {
    const raw = r.modelId || r.value;
    if (typeof raw !== "string" || !raw) return [];
    const id = cliID(raw);
    const name = typeof r.name === "string" ? r.name : id;
    return [option(id, kind === "kimi" ? name.replace(/ \(thinking\)/g, "") : name,
      typeof current === "string" && cliID(current) === id)];
  }));
}
function parseList(output, kind) {
  const text = output.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "");
  let json;
  try { json = JSON.parse(text); } catch { /* Some CLIs return terminal tables. */ }
  const rows = Array.isArray(json) ? json : json?.models || json?.data;
  if (Array.isArray(rows)) return unique(rows.flatMap((r) => {
    if (typeof r === "string") return [option(r)];
    if (!r || r.hidden || r.is_enabled === false) return [];
    const id = r.id || r.modelId;
    return typeof id === "string" ? [option(id, r.displayName || r.display_name || r.name || id, r.isDefault === true)] : [];
  }));
  const result = unique(text.split(/\r?\n/).flatMap((line) => {
    const row = line.trim().replace(/^[|│]\s*/, "").replace(/^[-•*] /, "");
    const match = kind === "opencode"
      ? row.match(/^([A-Za-z0-9_.:-]+\/[^\s]+)$/)
      : row.match(/^([A-Za-z0-9_][A-Za-z0-9_./:@+-]*)(?:\s+-\s+|:\s+|\s*[|│]\s*|\s{2,}|$)(.*)$/);
    if (!match || ["id", "model", "models", "name", "available", "available-models", "error", "warning"].includes(match[1].toLowerCase())) return [];
    return [option(match[1], match[2]?.trim() || match[1])];
  }));
  if (!result.length) throw failure();
  return result;
}
async function nativeModels(profile, { timeout = 15000 } = {}) {
  if (!supported.includes(profile.kind)) throw Error("此接入未提供自动模型查询，请使用客户端配置。");
  const kind = profile.kind;
  const acp = ["codebuddy", "kimi"].includes(kind);
  const rpc = acp || ["claude", "pi"].includes(kind);
  const args = {
    claude: ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--tools", "", "--strict-mcp-config", "--safe-mode", "--no-session-persistence"],
    codebuddy: ["--acp", "--tools", "", "--strict-mcp-config"],
    kimi: ["acp"],
    pi: ["--mode", "rpc", "--no-session", "--no-tools", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-context-files"],
    opencode: ["models"], cursor: ["--list-models"], qoder: ["--list-models"],
  }[kind];
  let spec;
  for (const command of profile.executable ? [profile.executable] : nativeCommands[kind]) {
    try { spec = resolveCommand(command, args); break; } catch { /* Try the documented alias. */ }
  }
  if (!spec) throw Error("未找到智能体命令，请在设置中配置路径。");
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), "MirrorModels-"));
  try {
    return await new Promise((resolve, reject) => {
      const child = spawn(spec.command, spec.args, { cwd: workspace, windowsHide: true,
        env: { ...spec.env, NO_COLOR: "1", TERM: "dumb", ...(kind === "opencode" ? { OPENCODE_DISABLE_DEFAULT_PLUGINS: "true" } : {}) },
        stdio: ["pipe", "pipe", "ignore"] });
      const decoder = new StringDecoder("utf8");
      let buffer = "", size = 0, settled = false;
      function finish(error, rows) {
        if (settled) return;
        settled = true; clearTimeout(timer);
        child.stdin.destroy();
        if (child.exitCode === null) {
          child.kill();
          const force = setTimeout(() => { if (child.exitCode === null) child.kill("SIGKILL"); }, 500);
          force.unref(); child.once("close", () => clearTimeout(force));
        }
        if (error) reject(error); else resolve(rows);
      }
      const timer = setTimeout(() => finish(Error("模型查询超时，请检查 CLI 版本与登录；仍可手动填写。")), timeout);
      const send = (request) => child.stdin.write(JSON.stringify(request) + "\n");
      child.on("error", () => finish(Error("无法启动模型查询命令。")));
      child.stdin.on("error", () => finish(failure()));
      child.stdout.on("data", (chunk) => {
        if (settled) return;
        size += chunk.length;
        if (size > 2_000_000) return finish(Error("模型列表超出大小限制。"));
        buffer += decoder.write(chunk);
        if (!rpc) return;
        while (buffer.includes("\n") && !settled) {
          const end = buffer.indexOf("\n"), line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
          let object;
          try { object = JSON.parse(line); } catch { continue; }
          try {
            if (acp) {
              if (object.method && object.id !== undefined) {
                send({ jsonrpc: "2.0", id: object.id, error: { code: -32601, message: "Metadata client does not support client actions" } });
                continue;
              }
              if (!["mirror-initialize", "mirror-models"].includes(object.id)) continue;
              if (object.error || !object.result) throw failure();
              if (object.id === "mirror-initialize") send({ jsonrpc: "2.0", id: "mirror-models", method: "session/new", params: { cwd: workspace, mcpServers: [] } });
              else finish(null, parseACP(object.result, kind));
            } else if (kind === "claude" && object.type === "control_response" && object.response?.request_id === "mirror-models") {
              const r = object.response;
              if (r.subtype !== "success" || !Array.isArray(r.response?.models)) throw failure();
              finish(null, unique(r.response.models.flatMap((m) => typeof m.value === "string"
                ? [option(m.value, m.displayName || m.value, m.value === "default", m.supportedEffortLevels || (m.supportsEffort === false ? [] : undefined))] : [])));
            } else if (kind === "pi" && object.type === "response" && object.id === "mirror-models" && object.command === "get_available_models") {
              if (!object.success || !Array.isArray(object.data?.models)) throw failure();
              finish(null, unique(object.data.models.flatMap((m) => typeof m.id === "string" && typeof m.provider === "string" && m.id && m.provider
                ? [option(`${m.provider}/${m.id}`, m.name || m.id, false, m.reasoning === false ? [] : undefined)] : [])));
            }
          } catch (error) { finish(error); }
        }
      });
      child.on("close", (code) => {
        if (settled) return;
        if (code !== 0 || rpc) return finish(Error("模型查询失败，请检查 CLI 版本与登录；仍可手动填写。"));
        try { finish(null, parseList(buffer + decoder.end(), kind)); } catch (error) { finish(error); }
      });
      if (acp) send({ jsonrpc: "2.0", id: "mirror-initialize", method: "initialize", params: { protocolVersion: 1, clientCapabilities: {}, clientInfo: { name: "Mirror", version: "1" } } });
      else if (kind === "claude") send({ type: "control_request", request_id: "mirror-models", request: { subtype: "initialize" } });
      else if (kind === "pi") send({ id: "mirror-models", type: "get_available_models" });
      else child.stdin.end();
    });
  } finally { await fs.rm(workspace, { recursive: true, force: true }); }
}
module.exports = { nativeModels, parseList, parseACP, supported };

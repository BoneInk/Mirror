import React, { useState } from "react";
import { themes } from "./themes";
import { version } from "../package.json";
const api = (name, ...args) => window.mirror.call(name, ...args);
const connection = (p) =>
  p.connection ||
  (p.kind === "http" ? "http" : p.kind === "custom" ? "command" : "native");
const efforts = (p) =>
  p.kind === "codex"
    ? ["", "none", "minimal", "low", "medium", "high", "xhigh"]
    : p.kind === "claude"
      ? ["", "low", "medium", "high", "xhigh", "max"]
      : p.kind === "pi"
        ? ["", "off", "minimal", "low", "medium", "high", "xhigh", "max"]
        : [""];
export function Typography({ config, onChange }) {
  const patch = (value) => onChange({ ...config, ...value });
  return (
    <div className="typography-fields">
      <label className="field">
        阅读字体
        <select
          aria-label="阅读字体"
          value={config.readingFont || "Georgia, 'SimSun', serif"}
          onChange={(e) => patch({ readingFont: e.target.value })}
        >
          <option value="Georgia, 'SimSun', serif">宋体 / Georgia</option>
          <option value="'Microsoft YaHei', sans-serif">微软雅黑</option>
          <option value="'KaiTi', Georgia, serif">楷体 / Georgia</option>
          <option value="Consolas, monospace">等宽字体</option>
        </select>
      </label>
      {[
        ["previewSize", "阅读字号", 13, 28, 1, 17],
        ["lineHeight", "行距", 1.3, 2.5, 0.1, 1.9],
        ["contentWidth", "阅读宽度", 480, 1200, 40, 720],
      ].map(([key, label, min, max, step, fallback]) => (
        <label className="field" key={key}>
          {label} · {config[key] || fallback}
          <input
            aria-label={label}
            type="range"
            min={min}
            max={max}
            step={step}
            value={config[key] || fallback}
            onChange={(e) => patch({ [key]: Number(e.target.value) })}
          />
        </label>
      ))}
    </div>
  );
}
export function Preferences({
  config,
  onChange,
  onClose,
  safely,
  toast,
  Modal,
  Button,
}) {
  const [page, setPage] = useState("appearance");
  const [id, setID] = useState(config.selectedAgent);
  const [draft, setDraft] = useState(
    config.profiles.find((p) => p.id === id) || config.profiles[0],
  );
  const [token, setToken] = useState("");
  const [models, setModels] = useState([]);
  const [busy, setBusy] = useState(false);
  const [detected, setDetected] = useState([]);
  const patch = (v) => setDraft((d) => ({ ...d, ...v }));
  const update = (v) => onChange({ ...config, ...v });
  const save = () =>
    safely(async () => {
      const next = {
        ...config,
        selectedAgent: draft.id,
        profiles: config.profiles.map((p) => (p.id === draft.id ? draft : p)),
      };
      await api("settings-save", next);
      if (token) await api("credential-save", draft.id, token);
      onChange(next);
      setToken("");
      toast("智能体配置已保存");
    });
  const loadModels = () =>
    safely(async () => {
      setBusy(true);
      try {
        if (token) await api("credential-save", draft.id, token);
        const result = await api("agent-models", draft);
        setModels(result);
        if (!result.length) toast("未提供模型列表，可以手动填写模型 ID");
      } finally {
        setBusy(false);
      }
    });
  return (
    <Modal title="设置" onClose={onClose} wide>
      <div className="settings-layout">
        <nav>
          {[
            ["appearance", "外观与编辑"],
            ["reading", "阅读排版"],
            ["agents", "智能体"],
            ["about", "关于 Mirror"],
          ].map(([key, label]) => (
            <button
              key={key}
              className={page === key ? "active" : ""}
              onClick={() => setPage(key)}
            >
              {label}
            </button>
          ))}
        </nav>
        <div className="settings-content">
          {page === "appearance" && (
            <>
              <h3>让空间适合你的思考</h3>
              <p className="muted">沿用 macOS 主题，设置自动保留在本机。</p>
              <div className="theme-cards">
                {[
                  ...themes,
                  ...(config.customThemes || []),
                  { id: "system", name: "跟随系统", background: "#888" },
                ].map((t) => (
                  <button
                    key={t.id}
                    className={config.theme === t.id ? "active" : ""}
                    onClick={() => update({ theme: t.id })}
                  >
                    <i
                      style={{
                        background: t.background,
                        border: `1px solid ${t.accent || "#aaa"}`,
                      }}
                    />
                    <span>{t.name}</span>
                  </button>
                ))}
              </div>
              <label className="field">
                编辑器字号 · {config.fontSize} px
                <input
                  aria-label="编辑器字号"
                  type="range"
                  min="13"
                  max="24"
                  value={config.fontSize}
                  onChange={(e) => update({ fontSize: Number(e.target.value) })}
                />
              </label>
              <label className="field">
                滚动同步
                <select
                  aria-label="滚动同步"
                  value={config.scrollSync || "smart"}
                  onChange={(e) => update({ scrollSync: e.target.value })}
                >
                  {[
                    ["smart", "智能同步"],
                    ["top", "顶部对齐"],
                    ["center", "居中对齐"],
                    ["off", "关闭"],
                  ].map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
              <label className="field">
                缩进宽度
                <select
                  value={config.tabWidth || 2}
                  onChange={(e) => update({ tabWidth: Number(e.target.value) })}
                >
                  <option value="2">2 空格</option>
                  <option value="4">4 空格</option>
                </select>
              </label>
              {[
                ["wordWrap", "自动换行", true],
                ["spellCheck", "拼写检查", false],
                ["autoPair", "自动补全括号", false],
                ["typewriter", "打字机模式", false],
              ].map(([key, label, fallback]) => (
                <label className="check-field" key={key}>
                  <input
                    type="checkbox"
                    checked={config[key] ?? fallback}
                    onChange={(e) => update({ [key]: e.target.checked })}
                  />
                  {label}
                </label>
              ))}
              <p className="muted">
                草稿自动保留；Ctrl S 保存到文件，Ctrl Shift S 另存为。
              </p>
              <Button
                onClick={() => {
                  const t = {
                    ...(themes.find((t) => t.id === config.theme) || themes[0]),
                    id: crypto.randomUUID(),
                    name: "自定义主题",
                  };
                  update({
                    theme: t.id,
                    customThemes: [...(config.customThemes || []), t],
                  });
                }}
              >
                创建自定义主题
              </Button>
              {(config.customThemes || [])
                .filter((t) => t.id === config.theme)
                .map((t) => (
                  <div className="theme-custom" key={t.id}>
                    <label>
                      名称
                      <input
                        value={t.name}
                        onChange={(e) =>
                          update({
                            customThemes: config.customThemes.map((v) =>
                              v.id === t.id
                                ? { ...v, name: e.target.value }
                                : v,
                            ),
                          })
                        }
                      />
                    </label>
                    {[
                      ["background", "纸张"],
                      ["text", "文字"],
                      ["accent", "强调色"],
                      ["code", "画布"],
                      ["muted", "次要文字"],
                      ["line", "边线"],
                    ].map(([key, label]) => (
                      <label key={key}>
                        {label}
                        <input
                          type="color"
                          value={t[key]}
                          onChange={(e) =>
                            update({
                              customThemes: config.customThemes.map((v) =>
                                v.id === t.id
                                  ? { ...v, [key]: e.target.value }
                                  : v,
                              ),
                            })
                          }
                        />
                      </label>
                    ))}
                    <label>
                      <input
                        type="checkbox"
                        checked={t.dark}
                        onChange={(e) =>
                          update({
                            customThemes: config.customThemes.map((v) =>
                              v.id === t.id
                                ? { ...v, dark: e.target.checked }
                                : v,
                            ),
                          })
                        }
                      />
                      深色图表
                    </label>
                    <Button
                      onClick={() =>
                        update({
                          theme: "light",
                          customThemes: config.customThemes.filter(
                            (v) => v.id !== t.id,
                          ),
                        })
                      }
                    >
                      删除主题
                    </Button>
                  </div>
                ))}
            </>
          )}
          {page === "reading" && (
            <Typography config={config} onChange={onChange} />
          )}
          {page === "agents" && (
            <>
              <h3>接着用你熟悉的 AI 工具</h3>
              <p className="muted">
                发送提问时传递引用和当前对话。已有对话保留创建时的配置。
              </p>
              <Button
                onClick={() =>
                  safely(async () => setDetected(await api("agent-discover")))
                }
              >
                检测本地智能体
              </Button>
              <label className="field">
                连接配置
                <select
                  aria-label="连接配置"
                  value={id}
                  onChange={(e) => {
                    setID(e.target.value);
                    setDraft(
                      config.profiles.find((p) => p.id === e.target.value),
                    );
                    setModels([]);
                    setToken("");
                  }}
                >
                  {config.profiles.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
              </label>
              <p className="muted">
                {detected.find((p) => p.id === id)?.status}
              </p>
              <label className="field">
                配置名称
                <input
                  value={draft.name}
                  onChange={(e) => patch({ name: e.target.value })}
                />
              </label>
              <label className="field">
                连接方式
                <select
                  aria-label="连接方式"
                  value={connection(draft)}
                  onChange={(e) => patch({ connection: e.target.value })}
                >
                  {["native", "http", "smartwork", "workbuddy", "command"].map(
                    (value) => (
                      <option value={value} key={value}>
                        {
                          {
                            native: "原生 CLI",
                            http: "兼容 HTTP",
                            smartwork: "Smartwork 协议",
                            workbuddy: "WorkBuddy Open API",
                            command: "自定义命令",
                          }[value]
                        }
                      </option>
                    ),
                  )}
                </select>
              </label>
              {["http", "smartwork", "workbuddy"].includes(
                connection(draft),
              ) ? (
                <>
                  <label className="field">
                    基础地址
                    <input
                      value={draft.endpoint || ""}
                      onChange={(e) => patch({ endpoint: e.target.value })}
                    />
                  </label>
                  <label className="field">
                    API Key / Access Token
                    <input
                      type="password"
                      autoComplete="off"
                      value={token}
                      placeholder="留空保留现有密钥"
                      onChange={(e) => setToken(e.target.value)}
                    />
                  </label>
                  <Button
                    onClick={() =>
                      safely(async () => {
                        await api("credential-save", draft.id, "");
                        toast("密钥已删除");
                      })
                    }
                  >
                    删除已保存的密钥
                  </Button>
                </>
              ) : (
                <label className="field">
                  可执行文件
                  <input
                    value={draft.executable || ""}
                    placeholder="留空自动查找 PATH"
                    onChange={(e) => patch({ executable: e.target.value })}
                  />
                </label>
              )}
              {connection(draft) === "command" && (
                <label className="field">
                  参数（JSON 字符串数组）
                  <input
                    value={draft.arguments || "[]"}
                    onChange={(e) => patch({ arguments: e.target.value })}
                  />
                </label>
              )}
              <label className="field">
                模型 ID
                <input
                  list="mirror-models"
                  value={draft.model || ""}
                  placeholder="留空使用 CLI 默认模型；HTTP 服务须填写"
                  onChange={(e) => patch({ model: e.target.value, effort: "" })}
                />
                <datalist id="mirror-models">
                  {models.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.name}
                    </option>
                  ))}
                </datalist>
              </label>
              <Button disabled={busy} onClick={loadModels}>
                {busy ? "读取中…" : "读取模型列表"}
              </Button>
              <label className="field">
                思考深度
                <select
                  aria-label="思考深度"
                  value={draft.effort || ""}
                  onChange={(e) => patch({ effort: e.target.value })}
                >
                  {[
                    "",
                    ...new Set(
                      models.find((m) => m.id === draft.model)?.efforts ||
                        efforts(draft).filter(Boolean),
                    ),
                  ].map((value) => (
                    <option key={value} value={value}>
                      {value || "默认"}
                    </option>
                  ))}
                </select>
              </label>
              <p className="muted">
                {connection(draft) === "workbuddy"
                  ? "需授权 Token，保持电脑端在线。停止会结束等待；任务可能仍在 WorkBuddy 中运行。"
                  : connection(draft) === "smartwork"
                    ? "复用 Smartwork 客户端登录和模型。工具权限由客户端管理。"
                    : connection(draft) === "command"
                      ? "直接启动命令。stdin 接收引用和对话的 JSON，stdout 返回 UTF-8 文字。"
                      : "CLI 需安装并登录。服务密钥由 Windows 系统加密保管。"}
              </p>
              <div className="dialog-actions">
                <Button className="primary" onClick={save}>
                  保存并设为默认
                </Button>
                <Button
                  onClick={() => {
                    const p = {
                      ...draft,
                      id: crypto.randomUUID(),
                      name: draft.name + " 副本",
                    };
                    update({ profiles: [...config.profiles, p] });
                    setDraft(p);
                    setID(p.id);
                    setToken("");
                  }}
                >
                  复制配置
                </Button>
                {config.profiles.length > 1 && (
                  <Button
                    onClick={() => {
                      const profiles = config.profiles.filter(
                        (p) => p.id !== id,
                      );
                      update({
                        profiles,
                        selectedAgent:
                          config.selectedAgent === id
                            ? profiles[0].id
                            : config.selectedAgent,
                      });
                      setID(profiles[0].id);
                      setDraft(profiles[0]);
                    }}
                  >
                    删除配置
                  </Button>
                )}
              </div>
            </>
          )}
          {page === "about" && (
            <div className="about">
              <img src="./icon.png" alt="Mirror" />
              <h3>Mirror for Windows</h3>
              <p>{version} · 写作、阅读与对话</p>
              <p className="muted">
                纸张、主题、阅读工具、图表交互和智能体协议与 macOS
                同步。草稿、文档版本与对话保留在本机。
              </p>
              <p className="muted">
                Windows 支持 Markdown 和纯文本；macOS 的 Quick Look
                与桌面草稿预填依赖系统接口。
              </p>
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
export function ThreadPicker({
  profile,
  Modal,
  Button,
  safely,
  onClose,
  onSelect,
}) {
  const [threads, setThreads] = useState([]),
    [cursor, setCursor] = useState(null),
    [selected, setSelected] = useState(null),
    [history, setHistory] = useState(null),
    [busy, setBusy] = useState(false);
  const load = (next) =>
    safely(async () => {
      setBusy(true);
      try {
        const result = await api("codex-threads", profile, next);
        setThreads((values) =>
          next ? [...values, ...result.data] : result.data || [],
        );
        setCursor(result.nextCursor);
      } finally {
        setBusy(false);
      }
    });
  React.useEffect(() => {
    load(null);
  }, []);
  return (
    <Modal title="引用到 Codex 会话" onClose={onClose} wide>
      <p className="muted">
        选择原会话并预览历史。继续原会话前需退出 Codex 桌面客户端。
      </p>
      <div className="thread-picker">
        <div>
          {threads.map((t) => (
            <button
              className={selected?.id === t.id ? "active" : ""}
              key={t.id}
              onClick={() =>
                safely(async () => {
                  setSelected(t);
                  setHistory(null);
                  setHistory(await api("codex-history", profile, t.id));
                })
              }
            >
              <strong>{t.name || t.preview || t.id}</strong>
              <small>{t.cwd}</small>
            </button>
          ))}
          {cursor && (
            <Button disabled={busy} onClick={() => load(cursor)}>
              加载更多
            </Button>
          )}
          {busy && <p>读取会话中…</p>}
          {!busy && !threads.length && <p className="empty">暂无可用会话</p>}
        </div>
        <div className="thread-history">
          {history?.messages.map((m, i) => (
            <section key={i}>
              <small>{m.role === "user" ? "你" : "Codex"}</small>
              <pre>{m.content}</pre>
            </section>
          ))}
        </div>
      </div>
      <div className="dialog-actions">
        <Button
          disabled={!history}
          className="primary"
          onClick={() => onSelect(selected, history.messages)}
        >
          在 Mirror 继续原会话
        </Button>
      </div>
    </Modal>
  );
}

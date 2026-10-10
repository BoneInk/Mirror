import React, { useState, useEffect } from "react";
import {
  Sparkles,
  MessageSquare,
  Palette,
  Type,
  SlidersHorizontal,
  Info,
  Check,
} from "lucide-react";
import { isMissing, selectableProfiles } from "./agent-availability.mjs";
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
      {[
        ["editorFont", "写作字体", "Consolas, 'Microsoft YaHei UI', monospace"],
        ["codeFont", "代码字体", "Consolas, monospace"],
      ].map(([key, label, fallback]) => (
        <label className="field" key={key}>
          {label}
          <select
            aria-label={label}
            value={config[key] ?? fallback}
            onChange={(e) => patch({ [key]: e.target.value })}
          >
            <option value={fallback}>系统等宽字体</option>
            <option value="'Microsoft YaHei UI', sans-serif">微软雅黑</option>
            <option value="Georgia, SimSun, serif">宋体 / Georgia</option>
          </select>
        </label>
      ))}
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
        ["fontSize", "编辑器字号", 11, 28, 1, 16],
        ["editorLineSpacing", "编辑行间距", 0, 16, 0.5, 6],
        ["previewSize", "阅读字号", 11, 28, 1, 17],
        ["lineHeight", "行距", 1.3, 2.5, 0.1, 1.9],
        ["contentWidth", "阅读宽度", 480, 1200, 40, 720],
      ].map(([key, label, min, max, step, fallback]) => (
        <label className="field" key={key}>
          {label} · {config[key] ?? fallback}
          <input
            aria-label={label}
            type="range"
            min={min}
            max={max}
            step={step}
            value={config[key] ?? fallback}
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
  initialPage = "agents",
  discoveries = [],
  onDiscover,
  conversations = [],
  onConversationsChange,
  Modal,
  Button,
  updates,
  onRestartUpdate,
}) {
  const [page, setPage] = useState(initialPage);
  const [presets, setPresets] = useState([]);
  useEffect(() => {
    let live = true;
    api("agent-presets")
      .then((rows) => {
        if (live) setPresets(rows);
      })
      .catch(() => {});
    return () => {
      live = false;
    };
  }, []);
  const [id, setID] = useState(config.selectedAgent);
  const [draft, setDraft] = useState(
    config.profiles.find((p) => p.id === id) || config.profiles[0] || {},
  );
  const [token, setToken] = useState("");
  const [models, setModels] = useState([]);
  const [busy, setBusy] = useState(false);
  const detected = discoveries;
  const [scanning, setScanning] = useState(false);
  const [editing, setEditing] = useState(false);
  const [memoryQuery, setMemoryQuery] = useState("");
  const [deleting, setDeleting] = useState(null);
  const scan = () =>
    safely(async () => {
      setScanning(true);
      try {
        onDiscover(await api("agent-discover", config.profiles));
      } finally {
        setScanning(false);
      }
    });
  const edit = (profile) => {
    setID(profile.id);
    setDraft({ ...profile });
    setModels([]);
    setToken("");
    setEditing(true);
  };
  const visibleMemories = conversations.filter((c) =>
    [
      c.name,
      c.profile.name,
      c.reference.text,
      ...c.messages.map((m) => m.content),
    ].some((v) => v?.toLowerCase().includes(memoryQuery.toLowerCase())),
  );

  const patch = (v) => setDraft((d) => ({ ...d, ...v }));
  const update = (v) => onChange({ ...config, ...v });
  const save = () =>
    safely(async () => {
      const next = {
        ...config,
        selectedAgent: draft.id,
        profiles: config.profiles.some((p) => p.id === draft.id)
          ? config.profiles.map((p) => (p.id === draft.id ? draft : p))
          : [...config.profiles, draft],
      };
      await api("settings-save", next);
      if (token) await api("credential-save", draft.id, token);
      onChange(next);
      setToken("");
      toast("智能体配置已保存");
      setEditing(false);
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
    <>
      <Modal title="设置" onClose={onClose} wide className="preferences-modal">
        <div className="settings-layout">
          <nav aria-label="设置分类" role="tablist">
            {[
              ["agents", "智能体", Sparkles],
              ["memory", "气泡记忆", MessageSquare],
              ["appearance", "主题", Palette],
              ["reading", "阅读排版", Type],
              ["editor", "编辑", SlidersHorizontal],
              ["about", "关于 Mirror", Info],
            ].map(([key, label, Icon]) => (
              <button
                key={key}
                role="tab"
                aria-selected={page === key}
                className={page === key ? "active" : ""}
                onClick={() => setPage(key)}
              >
                <Icon size={20} strokeWidth={1.5} />
                {label}
              </button>
            ))}
          </nav>
          <div className="settings-content">
            {page === "appearance" && (
              <>
                <h3>主题</h3>
                <p className="muted">选择内置主题，或创建自己的配色。</p>
                <div className="theme-cards">
                  {[
                    ...themes,
                    ...(config.customThemes || []),
                    { id: "system", name: "跟随系统", background: "#888" },
                  ].map((t) => (
                    <button
                      key={t.id}
                      aria-label={t.name}
                      className={config.theme === t.id ? "active" : ""}
                      style={{ background: t.background, color: t.text }}
                      onClick={() => update({ theme: t.id })}
                    >
                      <div className="theme-swatches">
                        {[
                          t.accent || "#888",
                          t.text || "#777",
                          t.muted || "#aaa",
                          t.code || "#ddd",
                        ].map((color, i) => (
                          <i key={i} style={{ background: color }} />
                        ))}
                        {config.theme === t.id && <Check size={15} />}
                      </div>
                      <span>{t.name}</span>
                      <small>{t.dark ? "深色" : "浅色"}</small>
                    </button>
                  ))}
                </div>
                <Button
                  onClick={() => {
                    const t = {
                      ...(themes.find((t) => t.id === config.theme) ||
                        themes[0]),
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
              <>
                <h3>排版</h3>
                <p className="muted">
                  字体与间距同时用于编辑、阅读和实时预览。
                </p>
                <Typography config={config} onChange={onChange} />
                <div className="typography-sample">
                  <p>让想法，在纸上展开。</p>
                  <code>let idea = "Mirror"</code>
                </div>
              </>
            )}
            {page === "editor" && (
              <>
                <div className="settings-page-heading">
                  <h3>编辑</h3>
                  <Button
                    onClick={() =>
                      update({
                        fontSize: 16,
                        scrollSync: "smart",
                        tabWidth: 2,
                        wordWrap: true,
                        spellCheck: false,
                        autoPair: false,
                        typewriter: false,
                        showLineNumbers: false,
                        highlightCurrentLine: false,
                        preserveSingleLineBreaks: false,
                        autosaveDelay: 0.5,
                      })
                    }
                  >
                    重置
                  </Button>
                </div>
                <p className="muted">调整写作区域与编辑行为。</p>{" "}
                <label className="field">
                  编辑器字号 · {config.fontSize} px
                  <input
                    aria-label="编辑器字号"
                    type="range"
                    min="13"
                    max="24"
                    value={config.fontSize}
                    onChange={(e) =>
                      update({ fontSize: Number(e.target.value) })
                    }
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
                    onChange={(e) =>
                      update({ tabWidth: Number(e.target.value) })
                    }
                  >
                    <option value="2">2 空格</option>
                    <option value="4">4 空格</option>
                    <option value="8">8 空格</option>
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
                {[
                  ["showLineNumbers", "显示行号"],
                  ["highlightCurrentLine", "高亮当前行"],
                  ["preserveSingleLineBreaks", "在预览与导出中保留单行换行"],
                ].map(([key, label]) => (
                  <label className="check-field" key={key}>
                    <input
                      type="checkbox"
                      checked={!!config[key]}
                      onChange={(e) => update({ [key]: e.target.checked })}
                    />
                    {label}
                  </label>
                ))}
                <label className="field">
                  草稿自动保留延迟
                  <select
                    aria-label="草稿自动保留延迟"
                    value={config.autosaveDelay || 0.5}
                    onChange={(e) =>
                      update({ autosaveDelay: Number(e.target.value) })
                    }
                  >
                    {[0.5, 1.2, 2, 5].map((v) => (
                      <option key={v} value={v}>
                        {v} 秒
                      </option>
                    ))}
                  </select>
                </label>
              </>
            )}
            {page === "memory" && (
              <>
                <h3>气泡记忆</h3>
                <label className="check-field">
                  <input
                    type="checkbox"
                    checked={config.memoryEnabled !== false}
                    onChange={(e) =>
                      update({ memoryEnabled: e.target.checked })
                    }
                  />
                  记住引用位置和对话
                </label>
                <p className="muted">
                  关闭后保留已有记录，新对话不再写入本机记忆。
                </p>
                <label className="field">
                  <input
                    aria-label="搜索气泡记忆"
                    placeholder="搜索问题、文档或智能体"
                    value={memoryQuery}
                    onChange={(e) => setMemoryQuery(e.target.value)}
                  />
                </label>
                <div className="memory-list">
                  {visibleMemories.map((c) => (
                    <div key={c.id}>
                      <div>
                        <strong>
                          {c.messages.find((m) => m.role === "user")?.content ||
                            c.reference.text}
                        </strong>
                        <small>
                          {c.name} · {c.profile.name}
                        </small>
                      </div>
                      <Button
                        disabled={c.busy}
                        onClick={() => setDeleting([c.id])}
                      >
                        删除
                      </Button>
                    </div>
                  ))}
                  {!visibleMemories.length && (
                    <p className="empty">
                      {memoryQuery ? "没有匹配的记录" : "还没有保存的对话"}
                    </p>
                  )}
                </div>
                <div className="dialog-actions">
                  <span className="muted">
                    {conversations.length} 条本机记录
                  </span>
                  <Button
                    disabled={
                      !conversations.length || conversations.some((c) => c.busy)
                    }
                    onClick={() => setDeleting(conversations.map((c) => c.id))}
                  >
                    清空记录…
                  </Button>
                </div>
              </>
            )}

            {page === "agents" && (
              <>
                <div className="settings-page-heading">
                  <h3>智能体</h3>
                  <select
                    className="add-agent"
                    aria-label="添加智能体"
                    value=""
                    onChange={(e) => {
                      const profile = {
                        ...presets.find((p) => p.id === e.target.value),
                        id: crypto.randomUUID(),
                      };
                      edit(profile);
                    }}
                  >
                    <option value="" disabled>
                      添加…
                    </option>
                    {presets.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                      </option>
                    ))}
                  </select>
                  <Button disabled={scanning} onClick={scan}>
                    {scanning ? "检测中…" : "检测本机"}
                  </Button>
                </div>
                <p className="muted">
                  选择引用提问的默认智能体。已有对话继续使用创建时的配置。
                </p>
                <label className="field">
                  默认智能体
                  <select
                    aria-label="默认智能体"
                    value={config.selectedAgent}
                    onChange={(e) => update({ selectedAgent: e.target.value })}
                  >
                    {!selectableProfiles(config.profiles, discoveries).some(
                      (p) => p.id === config.selectedAgent,
                    ) && (
                      <option value={config.selectedAgent} disabled>
                        原默认智能体不可用，请重新选择
                      </option>
                    )}
                    {selectableProfiles(config.profiles, discoveries).map(
                      (p) => (
                        <option key={p.id} value={p.id}>
                          {p.name}
                        </option>
                      ),
                    )}
                  </select>
                </label>
                <div className="agent-list">
                  {selectableProfiles(config.profiles, discoveries).map((p) => (
                    <div key={p.id}>
                      <div>
                        <strong>{p.name}</strong>
                        <small
                          title={detected.find((d) => d.id === p.id)?.command}
                        >
                          {detected.find((d) => d.id === p.id)?.status ||
                            connection(p)}
                        </small>
                      </div>
                      <Button onClick={() => edit(p)}>配置…</Button>
                    </div>
                  ))}
                </div>
                <details className="missing-agents">
                  <summary>
                    未检测到的智能体（
                    {
                      config.profiles.filter((p) => isMissing(p, discoveries))
                        .length
                    }
                    ）
                  </summary>
                  <p className="muted">
                    这些智能体自动从对话选择器隐藏。安装 CLI
                    或填写命令路径后，点击「检测本机」即可恢复。
                  </p>
                  <div className="agent-list">
                    {config.profiles
                      .filter((p) => isMissing(p, discoveries))
                      .map((p) => (
                        <div key={p.id}>
                          <div>
                            <strong>{p.name}</strong>
                            <small>
                              {detected.find((d) => d.id === p.id)?.status}
                            </small>
                          </div>
                          <Button onClick={() => edit(p)}>配置…</Button>
                        </div>
                      ))}
                  </div>
                </details>
              </>
            )}
            {page === "about" && (
              <div className="about">
                <img src="./icon.png" alt="Mirror" />
                <h3>Mirror for Windows</h3>
                <p>{version} · 写作、阅读与对话</p>
                <label className="check-field">
                  <input type="checkbox" checked={config.automaticallyUpdates !== false}
                    onChange={(e) => update({ automaticallyUpdates: e.target.checked })} />
                  自动下载并安装更新
                </label>
                <p className="muted">每天检查 GitHub Releases，后台下载并校验，正常退出后安装。下次打开即为新版。</p>
                <p role="status">{updates?.status}</p>
                {updates?.availableVersion && <p>新版本：{updates.availableVersion}</p>}
                {updates?.busy && <progress aria-label="更新进度" value={updates.progress ?? undefined} max="100" />}
                {updates?.error && <p role="alert">{updates.error}</p>}
                <div className="dialog-actions">
                  <Button disabled={updates?.busy || updates?.ready} onClick={() => safely(() => api("update-check"))}>检查更新</Button>
                  {updates?.availableVersion && !updates?.ready && <Button disabled={updates?.busy} onClick={() => safely(() => api("update-download"))}>下载更新</Button>}
                  {updates?.ready && <Button onClick={onRestartUpdate}>立即重启更新</Button>}
                  {updates?.installer && !updates?.ready && <Button onClick={() => safely(() => api("update-installer"))}>打开安装包</Button>}
                </div>
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
      {editing && (
        <Modal title="配置智能体" onClose={() => setEditing(false)}>
          <div className="agent-editor">
            {" "}
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
            {["http", "smartwork", "workbuddy"].includes(connection(draft)) ? (
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
                    const profiles = config.profiles.filter((p) => p.id !== id);
                    update({
                      profiles,
                      selectedAgent:
                        config.selectedAgent === id
                          ? profiles[0].id
                          : config.selectedAgent,
                    });
                    setID(profiles[0].id);
                    setDraft(profiles[0]);
                    setEditing(false);
                  }}
                >
                  删除配置
                </Button>
              )}
            </div>
          </div>
        </Modal>
      )}
      {deleting && (
        <Modal title="删除本机对话记录" onClose={() => setDeleting(null)}>
          <p>删除 {deleting.length} 条记录及其文内标记？</p>
          <div className="dialog-actions">
            <Button onClick={() => setDeleting(null)}>取消</Button>
            <Button
              className="primary"
              onClick={() => {
                onConversationsChange(
                  conversations.filter((c) => !deleting.includes(c.id)),
                );
                setDeleting(null);
              }}
            >
              删除记录
            </Button>
          </div>
        </Modal>
      )}
    </>
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

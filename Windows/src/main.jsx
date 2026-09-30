import React, { useState, useEffect, useRef, useCallback } from "react";
import { createRoot } from "react-dom/client";
import {
  Folder,
  List,
  Search,
  Settings,
  FileText,
  Plus,
  X,
  Pencil,
  Columns2,
  BookOpen,
  Save,
  FolderOpen,
  PanelLeftClose,
  Command,
  Download,
  History,
  Sun,
  Moon,
  Sparkles,
  ArrowUp,
  Square,
  ChevronRight,
  ChevronDown,
  Minus,
  Maximize2,
  Check,
  Bold,
  Italic,
  Link,
  Code,
  Quote,
  ListTodo,
  Table,
  RefreshCw,
  Trash2,
  AlertCircle,
  MessageSquare,
  Focus,
  AlignLeft,
  ArrowLeft,
} from "lucide-react";
import { renderMarkdown, renderDiagrams, headings } from "./markdown";
import "./style.css";
const api = (name, ...args) => window.mirror.call(name, ...args);
const welcome = `# 让想法，在纸上展开\n\n一个安静的空间，容纳尚未成形的思考。\nMirror 把写作、阅读与对话放在同一张桌面上。\n\n## 从一张纸开始\n\n清晰的界面来自秩序：适度的留白、自然的层级，以及随手可用的工具。\n\n**把注意力留给内容**，让工具轻轻退到文字之后。\n\n> 写作不是把复杂的想法藏起来，而是给它一个可以展开的形状。\n\n### 今天想做的事\n\n- [x] 收集灵感，写下最初的几句话\n- [ ] 整理成一篇清晰的文章\n- [ ] 圈选一段内容，与 AI 讨论\n\n## 让结构自然浮现\n\n| 表达 | 方式 | 节奏 |\n| --- | --- | --- |\n| 草稿 | 自由记录 | 轻快 |\n| 阅读 | 梳理思路 | 从容 |\n| 对话 | 选中文字提问 | 深入 |\n\n### 从想法到文章\n\n\`\`\`mermaid\nflowchart LR\n  A[收集灵感] --> B[整理草稿]\n  B --> C[阅读与对话]\n  C --> D[分享文章]\n\`\`\`\n\n公式也可以离线显示：$E = mc^2$。\n\n---\n\n选中编辑器或预览中的文字，点击「提问」。在设置中连接你熟悉的智能体后，就能开始对话。\n`;
function newDoc(text = "", name = "未命名.md") {
  return {
    id: crypto.randomUUID(),
    name,
    text,
    savedText: text ? "" : text,
    path: null,
    stamp: null,
  };
}
function Button({ icon: Icon, children, className = "", ...props }) {
  return (
    <button className={`button ${className}`} {...props}>
      {Icon && <Icon size={16} strokeWidth={1.7} />}
      {children}
    </button>
  );
}
function Preview({ text, path, dark, innerRef, onMouseUp, onScroll, onLink }) {
  const ref = useRef();
  const html = React.useMemo(() => renderMarkdown(text, path), [text, path]);
  useEffect(() => {
    renderDiagrams(ref.current, dark);
  }, [html, dark]);
  return (
    <div
      className="preview-scroll"
      ref={innerRef}
      onMouseUp={onMouseUp}
      onScroll={onScroll}
    >
      <article
        className="prose"
        ref={ref}
        onClick={(event) => {
          const a = event.target.closest("a");
          if (a) {
            event.preventDefault();
            onLink(a.getAttribute("href"));
          }
        }}
        dangerouslySetInnerHTML={{ __html: html }}
      />
    </div>
  );
}
function Modal({ title, children, onClose, wide }) {
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <section
        className={`modal ${wide ? "wide" : ""}`}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <div className="modal-title">
          <h2>{title}</h2>
          <Button icon={X} title="关闭" aria-label="关闭" onClick={onClose} />
        </div>
        {children}
      </section>
    </div>
  );
}
function App() {
  const [ready, setReady] = useState(false);
  const [tabs, setTabs] = useState([]);
  const [active, setActive] = useState("");
  const [folder, setFolder] = useState(null);
  const [recent, setRecent] = useState([]);
  const [config, setConfig] = useState({
    theme: "light",
    mode: "split",
    fontSize: 16,
    selectedAgent: "codex",
    profiles: [],
  });
  const [sidebar, setSidebar] = useState("files");
  const [filter, setFilter] = useState("");
  const [focus, setFocus] = useState(false);
  const [dialog, setDialog] = useState(null);
  const [notice, setNotice] = useState("");
  const [selection, setSelection] = useState(null);
  const [conversations, setConversations] = useState([]);
  const [chatID, setChatID] = useState(null);
  const [question, setQuestion] = useState("");
  const [history, setHistory] = useState([]);
  const [systemDark, setSystemDark] = useState(
    matchMedia("(prefers-color-scheme: dark)").matches,
  );
  const [query, setQuery] = useState("");
  const [confirmClose, setConfirmClose] = useState(null);
  const editor = useRef();
  const preview = useRef();
  const current = useRef();
  const scrollSource = useRef(null);
  const pendingDraft = useRef();
  const doc = tabs.find((tab) => tab.id === active) || tabs[0];
  const dark =
    config.theme === "dark" || (config.theme === "system" && systemDark);
  const conversation = conversations.find((value) => value.id === chatID);
  const outline = headings(doc?.text || "");
  const dirty = doc && doc.text !== doc.savedText;
  current.current = { tabs, active, folder, config, conversations, ready };
  const toast = useCallback((text) => setNotice(text), []);
  const safely = useCallback(
    async (task) => {
      try {
        return await task();
      } catch (error) {
        toast(error.message);
        return null;
      }
    },
    [toast],
  );
  const session = () => ({
    tabs: current.current.tabs,
    active: current.current.active,
    folder: current.current.folder,
  });
  const addOpened = (file) => {
    const existing = current.current.tabs.find((tab) => tab.path === file.path);
    if (existing) {
      setActive(existing.id);
      return;
    }
    const tab = { ...file, id: crypto.randomUUID(), savedText: file.text };
    setTabs((values) => [...values, tab]);
    setActive(tab.id);
    setRecent((values) =>
      [file.path, ...values.filter((x) => x !== file.path)].slice(0, 12),
    );
  };
  useEffect(() => {
    let live = true;
    safely(async () => {
      const data = await api("bootstrap");
      if (!live) return;
      const saved = data.session.tabs?.length
        ? data.session.tabs
        : [newDoc(welcome, "专注与写作.md")];
      setTabs(saved);
      setActive(data.session.active || saved[0].id);
      setFolder(data.session.folder || null);
      setConfig(data.settings);
      setRecent(data.recent);
      setConversations(
        data.conversations.map((c) => ({
          ...c,
          busy: false,
          error: c.busy ? "上次生成已中断，可以继续提问。" : c.error,
        })),
      );
      setReady(true);
    });
    const media = matchMedia("(prefers-color-scheme: dark)");
    const change = (e) => setSystemDark(e.matches);
    media.addEventListener("change", change);
    const offOpen = window.mirror.on("file-opened", (file) => {
      if (current.current.ready) addOpened(file);
      else pendingDraft.current = file;
    });
    const offClose = window.mirror.on("close-request", () => {
      if (current.current.tabs.some((t) => t.text !== t.savedText))
        setConfirmClose("quit");
      else
        safely(async () => {
          await api("conversations-save", current.current.conversations);
          await api("settings-save", current.current.config);
          await api("quit-ready", session());
        });
    });
    const offAgent = window.mirror.on("agent-event", (event) =>
      setConversations((values) =>
        values.map((c) => {
          if (c.id !== event.id) return c;
          const messages = [...c.messages];
          const last = { ...messages[messages.length - 1] };
          if (event.type === "delta") last.content += event.delta;
          if (event.type === "done") last.content = event.content;
          messages[messages.length - 1] = last;
          return {
            ...c,
            messages,
            busy: event.type === "delta",
            error: event.type === "error" ? event.error : null,
          };
        }),
      ),
    );
    return () => {
      live = false;
      media.removeEventListener("change", change);
      offOpen();
      offClose();
      offAgent();
    };
  }, []);
  useEffect(() => {
    if (ready && pendingDraft.current) {
      addOpened(pendingDraft.current);
      pendingDraft.current = null;
    }
  }, [ready]);
  useEffect(() => {
    if (!ready) return;
    const timer = setTimeout(
      () => safely(() => api("session-save", session())),
      450,
    );
    return () => clearTimeout(timer);
  }, [tabs, active, folder, ready]);
  useEffect(() => {
    if (ready) safely(() => api("settings-save", config));
  }, [config, ready]);
  useEffect(() => {
    if (!ready) return;
    const timer = setTimeout(
      () => safely(() => api("conversations-save", conversations)),
      400,
    );
    return () => clearTimeout(timer);
  }, [conversations, ready]);
  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(""), 4500);
    return () => clearTimeout(timer);
  }, [notice]);
  useEffect(() => {
    setSelection(null);
  }, [active, config.mode]);
  const updateDoc = (patch) =>
    setTabs((values) =>
      values.map((tab) => (tab.id === doc.id ? { ...tab, ...patch } : tab)),
    );
  const openFile = () =>
    safely(async () => {
      const files = await api("open");
      files.forEach(addOpened);
    });
  const openFolder = () =>
    safely(async () => {
      const value = await api("folder");
      if (value) {
        setFolder(value);
        setSidebar("files");
      }
    });
  const save = (saveAs = false, target = doc) =>
    safely(async () => {
      if (!target) return false;
      const result = await api("save", target, saveAs);
      if (!result) return false;
      setTabs((values) =>
        values.map((tab) =>
          tab.id === target.id
            ? { ...tab, ...result, savedText: target.text }
            : tab,
        ),
      );
      setRecent((values) =>
        [result.path, ...values.filter((x) => x !== result.path)].slice(0, 12),
      );
      toast("已保存到本地");
      return true;
    });
  const create = () => {
    const tab = newDoc();
    setTabs((values) => [...values, tab]);
    setActive(tab.id);
  };
  const closeTab = (id) => {
    const tab = tabs.find((t) => t.id === id);
    if (tab.text !== tab.savedText) {
      setConfirmClose(id);
      return;
    }
    removeTab(id);
  };
  const removeTab = (id) => {
    let remaining = tabs.filter((t) => t.id !== id);
    if (!remaining.length) remaining = [newDoc()];
    setTabs(remaining);
    if (active === id) setActive(remaining[0].id);
  };
  const insert = (before, after = "") => {
    if (config.mode === "read") {
      setConfig((c) => ({ ...c, mode: "split" }));
      return;
    }
    const area = editor.current;
    const start = area.selectionStart;
    const end = area.selectionEnd;
    area.focus();
    document.execCommand(
      "insertText",
      false,
      before + area.value.slice(start, end) + after,
    );
    // Chromium's editing command keeps native undo history.
    if (area.value === doc.text)
      updateDoc({
        text:
          doc.text.slice(0, start) +
          before +
          doc.text.slice(start, end) +
          after +
          doc.text.slice(end),
      });
    area.setSelectionRange(start + before.length, end + before.length);
  };
  const selectedText = (source) => {
    let text = "";
    let start = 0;
    let end = 0;
    if (source === "editor") {
      start = editor.current.selectionStart;
      end = editor.current.selectionEnd;
      text = doc.text.slice(start, end);
    } else text = window.getSelection()?.toString() || "";
    if (text.trim())
      setSelection({
        text: text.slice(0, 20000),
        start,
        end,
        source,
        line:
          source === "editor"
            ? doc.text.slice(0, start).split("\n").length
            : null,
      });
    else setSelection(null);
  };
  const newConversation = () => {
    if (!selection) return;
    const profile = config.profiles.find((p) => p.id === config.selectedAgent);
    const c = {
      id: crypto.randomUUID(),
      docID: doc.id,
      path: doc.path,
      name: doc.name,
      reference: { text: selection.text, path: doc.path, line: selection.line },
      profile: { ...profile },
      messages: [],
      date: new Date().toISOString(),
      busy: false,
    };
    setConversations((values) => [...values, c]);
    setChatID(c.id);
    setQuestion("");
    setSelection(null);
  };
  const send = () =>
    safely(async () => {
      if (!question.trim() || !conversation || conversation.busy) return;
      const messages = [
        ...conversation.messages.filter((m) => m.content),
        { role: "user", content: question.trim() },
      ];
      setQuestion("");
      setConversations((values) =>
        values.map((c) =>
          c.id === chatID
            ? {
                ...c,
                messages: [...messages, { role: "assistant", content: "" }],
                busy: true,
                error: null,
              }
            : c,
        ),
      );
      try {
        await api("agent-start", {
          id: chatID,
          profile: conversation.profile,
          reference: conversation.reference,
          messages,
        });
      } catch (error) {
        setConversations((values) =>
          values.map((c) =>
            c.id === chatID ? { ...c, busy: false, error: error.message } : c,
          ),
        );
      }
    });
  const exportDocument = (format) =>
    safely(async () => {
      const host = document.createElement("div");
      host.innerHTML = renderMarkdown(doc.text, doc.path);
      document.body.appendChild(host);
      host.className = "export-staging";
      try {
        await renderDiagrams(host, dark);
        const result = await api("export", {
          html: host.innerHTML,
          format,
          name: doc.name,
          dark: false,
        });
        if (result) toast(`已导出 ${format.toUpperCase()}`);
      } finally {
        host.remove();
      }
    });
  const syncScroll = (source, target, name) => {
    if (
      !source ||
      !target ||
      (scrollSource.current && scrollSource.current !== name)
    )
      return;
    scrollSource.current = name;
    const ratio =
      source.scrollTop / Math.max(1, source.scrollHeight - source.clientHeight);
    target.scrollTop = ratio * (target.scrollHeight - target.clientHeight);
    setTimeout(() => {
      scrollSource.current = null;
    }, 60);
  };
  const jump = (heading) => {
    if (editor.current) {
      const offset =
        doc.text.split("\n").slice(0, heading.line).join("\n").length +
        (heading.line ? 1 : 0);
      editor.current.focus();
      editor.current.setSelectionRange(offset, offset);
      editor.current.scrollTop = heading.line * config.fontSize * 1.9;
    }
    const nodes = preview.current?.querySelectorAll("h1,h2,h3,h4,h5,h6");
    const index = outline.indexOf(heading);
    nodes?.[index]?.scrollIntoView({ behavior: "smooth", block: "start" });
    if (index < 0 && preview.current) {
      preview.current.scrollTop =
        (heading.line / Math.max(1, doc.text.split("\n").length - 1)) *
        (preview.current.scrollHeight - preview.current.clientHeight);
    }
  };
  const handleLink = (value) => {
    if (value?.startsWith("#")) {
      const target = decodeURIComponent(value.slice(1))
        .replace(/-/g, " ")
        .toLowerCase();
      const h = outline.find((h) => h.text.toLowerCase() === target);
      if (h) jump(h);
    } else if (/^https?:/i.test(value || ""))
      safely(() => api("external", value));
    else toast("本地链接请通过文件侧栏或「打开文件」打开。");
  };
  useEffect(() => {
    const key = (event) => {
      if (event.key === "Escape") {
        setDialog(null);
        setSelection(null);
        setChatID(null);
        setConfirmClose(null);
        setFocus(false);
      }
      if (!event.ctrlKey) return;
      const value = event.key.toLowerCase();
      if (["s", "o", "n", "p", "b", "i", "k"].includes(value))
        event.preventDefault();
      if (value === "s") save(event.shiftKey);
      if (value === "o") event.shiftKey ? openFolder() : openFile();
      if (value === "n") create();
      if (value === "p") {
        setQuery("");
        setDialog("commands");
      }
      if (value === "b" && event.target === editor.current) insert("**", "**");
      if (value === "i" && event.target === editor.current) insert("*", "*");
      if (value === "k" && event.target === editor.current)
        insert("[", "](https://)");
      if (event.key === "1") {
        event.preventDefault();
        setConfig((c) => ({ ...c, mode: "edit" }));
      }
      if (event.key === "2") {
        event.preventDefault();
        setConfig((c) => ({ ...c, mode: "split" }));
      }
      if (event.key === "3") {
        event.preventDefault();
        setConfig((c) => ({ ...c, mode: "read" }));
      }
    };
    document.addEventListener("keydown", key);
    return () => document.removeEventListener("keydown", key);
  });
  const commands = [
    ["新建文档", "Ctrl N", create],
    ["打开文件", "Ctrl O", openFile],
    ["打开文件夹", "Ctrl Shift O", openFolder],
    ["保存", "Ctrl S", () => save()],
    ["另存为", "Ctrl Shift S", () => save(true)],
    ["源码编辑", "Ctrl 1", () => setConfig((c) => ({ ...c, mode: "edit" }))],
    ["分栏预览", "Ctrl 2", () => setConfig((c) => ({ ...c, mode: "split" }))],
    ["沉浸阅读", "Ctrl 3", () => setConfig((c) => ({ ...c, mode: "read" }))],
    ["专注模式", "", () => setFocus(true)],
    ["导出 HTML", "", () => exportDocument("html")],
    ["导出 PDF", "", () => exportDocument("pdf")],
    ["设置", "", () => setDialog("settings")],
  ];
  if (!ready || !doc)
    return (
      <div className="loading">正在打开 Mirror…{notice && <p>{notice}</p>}</div>
    );
  return (
    <div
      className={`app ${dark ? "dark" : ""} ${focus ? "focus-mode" : ""}`}
      style={{ "--editor-size": `${config.fontSize}px` }}
    >
      <header className="topbar">
        <div className="brand">
          <img src="./icon.png" alt="" />
          <strong>Mirror</strong>
          <span className="platform">WINDOWS</span>
        </div>
        <div className="title-document">
          <strong>
            {doc.name.replace(/\.(md|markdown)$/i, "")}
            {dirty && <span className="dirty-dot" />}
          </strong>
          <small>{folder?.name || "本地写作空间"}</small>
        </div>
        <div className="top-actions">
          <div className="mode-switch">
            {[
              ["edit", Pencil, "编辑"],
              ["split", Columns2, "分栏"],
              ["read", BookOpen, "阅读"],
            ].map(([mode, Icon, label]) => (
              <Button
                key={mode}
                icon={Icon}
                className={config.mode === mode ? "active" : ""}
                title={`Ctrl ${mode === "edit" ? 1 : mode === "split" ? 2 : 3}`}
                onClick={() => setConfig((c) => ({ ...c, mode }))}
              >
                {label}
              </Button>
            ))}
          </div>
          <Button
            icon={Save}
            title="保存 (Ctrl S)"
            aria-label="保存"
            onClick={() => save()}
          />
          <Button
            icon={Command}
            title="命令 (Ctrl P)"
            aria-label="命令"
            onClick={() => {
              setQuery("");
              setDialog("commands");
            }}
          />
          <Button
            icon={Download}
            title="导出"
            aria-label="导出"
            onClick={() => setDialog("export")}
          />
        </div>
        <div className="window-controls">
          <button aria-label="最小化" onClick={() => api("window", "minimize")}>
            <Minus size={14} />
          </button>
          <button aria-label="最大化" onClick={() => api("window", "maximize")}>
            <Maximize2 size={12} />
          </button>
          <button
            className="window-close"
            aria-label="关闭窗口"
            onClick={() => api("window", "close")}
          >
            <X size={16} />
          </button>
        </div>
      </header>
      {!focus && (
        <div className="tabbar">
          <div className="tabs">
            {tabs.map((tab) => (
              <div
                className={`tab ${tab.id === doc.id ? "selected" : ""}`}
                key={tab.id}
              >
                <button onClick={() => setActive(tab.id)}>
                  <FileText size={14} />
                  <span>{tab.name.replace(/\.md$/i, "")}</span>
                  {tab.text !== tab.savedText && <span className="dirty-dot" />}
                </button>
                <button
                  aria-label={`关闭 ${tab.name}`}
                  onClick={() => closeTab(tab.id)}
                >
                  <X size={13} />
                </button>
              </div>
            ))}
          </div>
          <Button
            icon={Plus}
            aria-label="新建文档"
            title="新建 (Ctrl N)"
            onClick={create}
          />
        </div>
      )}
      <div className="body">
        {!focus && (
          <nav className="rail" aria-label="导航">
            {[
              ["files", Folder, "文件"],
              ["outline", List, "大纲"],
              ["search", Search, "查找"],
              ["chats", MessageSquare, "对话"],
            ].map(([id, Icon, label]) => (
              <button
                key={id}
                className={sidebar === id ? "active" : ""}
                onClick={() => setSidebar(sidebar === id ? null : id)}
              >
                <Icon size={21} strokeWidth={1.6} />
                <span>{label}</span>
              </button>
            ))}
            <div className="rail-bottom">
              <button onClick={() => setFocus(true)} title="专注模式">
                <Focus size={21} />
                <span>专注</span>
              </button>
              <button onClick={() => setDialog("settings")}>
                <Settings size={21} strokeWidth={1.6} />
                <span>设置</span>
              </button>
            </div>
          </nav>
        )}
        {!focus && sidebar && (
          <aside className="sidebar">
            <div className="sidebar-title">
              <div>
                <small>
                  {sidebar === "files"
                    ? "WORKSPACE"
                    : sidebar === "outline"
                      ? "CONTENTS"
                      : sidebar === "chats"
                        ? "CONVERSATIONS"
                        : "FIND IN DOCUMENT"}
                </small>
                <h3>
                  {sidebar === "files"
                    ? folder?.name || "本地文档"
                    : sidebar === "outline"
                      ? "文章大纲"
                      : sidebar === "chats"
                        ? "选区对话"
                        : "文内查找"}
                </h3>
              </div>
              <Button
                icon={sidebar === "files" ? FolderOpen : PanelLeftClose}
                aria-label={sidebar === "files" ? "打开文件夹" : "隐藏侧栏"}
                title={sidebar === "files" ? "打开文件夹" : "隐藏侧栏"}
                onClick={
                  sidebar === "files" ? openFolder : () => setSidebar(null)
                }
              />
            </div>
            {sidebar === "files" && (
              <>
                <div className="filter">
                  <Search size={14} />
                  <input
                    placeholder="筛选文件…"
                    value={filter}
                    onChange={(e) => setFilter(e.target.value)}
                    aria-label="筛选文件"
                  />
                </div>
                <div className="file-list">
                  {folder
                    ? folder.files
                        .filter((f) =>
                          f.relative
                            .toLowerCase()
                            .includes(filter.toLowerCase()),
                        )
                        .map((f) => (
                          <button
                            title={f.relative}
                            key={f.path}
                            className={doc.path === f.path ? "selected" : ""}
                            onClick={() =>
                              safely(async () =>
                                addOpened(await api("open", f.path)),
                              )
                            }
                          >
                            <FileText size={15} />
                            <span>{f.relative}</span>
                          </button>
                        ))
                    : tabs
                        .filter((t) => t.name.includes(filter))
                        .map((t) => (
                          <button
                            key={t.id}
                            className={t.id === doc.id ? "selected" : ""}
                            onClick={() => setActive(t.id)}
                          >
                            <FileText size={15} />
                            <span>{t.name}</span>
                          </button>
                        ))}
                  {!folder && (
                    <div className="workspace-hint">
                      <p>文字就在你的电脑上。</p>
                      <Button icon={FolderOpen} onClick={openFolder}>
                        打开文件夹
                      </Button>
                      <Button icon={FileText} onClick={openFile}>
                        打开 Markdown
                      </Button>
                    </div>
                  )}
                </div>
                <div className="recent">
                  <div className="section-label">最近打开</div>
                  {recent.slice(0, 5).map((file) => (
                    <button
                      key={file}
                      title={file}
                      onClick={() =>
                        safely(async () =>
                          addOpened(await api("recent-open", file)),
                        )
                      }
                    >
                      <FileText size={15} />
                      <div>
                        <strong>{file.split(/[\\/]/).pop()}</strong>
                        <small>{file.split(/[\\/]/).slice(-2, -1)}</small>
                      </div>
                    </button>
                  ))}
                </div>
                <div className="sidebar-footer">
                  <span>{folder?.files.length || tabs.length} 个文件</span>
                  {folder && (
                    <button
                      aria-label="刷新文件夹"
                      onClick={() =>
                        safely(async () =>
                          setFolder({
                            ...folder,
                            files: await api("folder-refresh", folder.root),
                          }),
                        )
                      }
                    >
                      <RefreshCw size={13} />
                    </button>
                  )}
                </div>
              </>
            )}
            {sidebar === "outline" && (
              <div className="outline">
                {outline.length ? (
                  outline.map((h, i) => (
                    <button
                      key={i}
                      style={{ paddingLeft: 16 + (h.level - 1) * 12 }}
                      onClick={() => jump(h)}
                    >
                      <span className="heading-level">H{h.level}</span>
                      {h.text}
                    </button>
                  ))
                ) : (
                  <p className="empty">用 # 标题组织文章，结构会在这里浮现。</p>
                )}
              </div>
            )}
            {sidebar === "search" && (
              <>
                <div className="filter">
                  <Search size={14} />
                  <input
                    placeholder="查找文字…"
                    aria-label="查找文字"
                    value={filter}
                    onChange={(e) => setFilter(e.target.value)}
                  />
                </div>
                <div className="search-results">
                  {filter &&
                    doc.text.split("\n").map(
                      (line, i) =>
                        line.toLowerCase().includes(filter.toLowerCase()) && (
                          <button key={i} onClick={() => jump({ line: i })}>
                            <small>第 {i + 1} 行</small>
                            <span>{line}</span>
                          </button>
                        ),
                    )}
                </div>
              </>
            )}
            {sidebar === "chats" && (
              <div className="conversation-list">
                {conversations
                  .filter(
                    (c) =>
                      c.docID === doc.id || (c.path && c.path === doc.path),
                  )
                  .map((c) => (
                    <div
                      className={c.id === chatID ? "selected" : ""}
                      key={c.id}
                    >
                      <button
                        onClick={() => {
                          setChatID(c.id);
                          setQuestion("");
                        }}
                      >
                        <MessageSquare size={14} />
                        <span>{c.reference.text.slice(0, 50)}</span>
                        <small>{c.profile.name}</small>
                      </button>
                      <button
                        title="删除对话"
                        aria-label="删除对话"
                        onClick={() => {
                          if (c.busy) safely(() => api("agent-stop", c.id));
                          setConversations((values) =>
                            values.filter((v) => v.id !== c.id),
                          );
                          if (chatID === c.id) setChatID(null);
                        }}
                      >
                        <Trash2 size={13} />
                      </button>
                    </div>
                  ))}
                {!conversations.some(
                  (c) => c.docID === doc.id || (c.path && c.path === doc.path),
                ) && (
                  <p className="empty">
                    选中一段文字开始提问。讨论会保留在这里。
                  </p>
                )}
              </div>
            )}
          </aside>
        )}
        <main className={`workspace mode-${config.mode}`}>
          {config.mode !== "read" && (
            <section className="editor-pane">
              <div className="pane-title">
                <span>MARKDOWN</span>
                <div className="format-tools">
                  {[
                    [Bold, "**", "**", "粗体"],
                    [Italic, "*", "*", "斜体"],
                    [Link, "[", "](https://)", "链接"],
                    [Code, "`", "`", "代码"],
                    [Quote, "> ", "", "引用"],
                    [ListTodo, "- [ ] ", "", "待办"],
                    [
                      Table,
                      "\n| 标题 | 标题 |\n| --- | --- |\n| 内容 | 内容 |\n",
                      "",
                      "表格",
                    ],
                  ].map(([Icon, a, b, label]) => (
                    <Button
                      key={label}
                      icon={Icon}
                      aria-label={label}
                      title={label}
                      onMouseDown={(e) => e.preventDefault()}
                      onClick={() => insert(a, b)}
                    />
                  ))}
                </div>
                <span className="source-label">Source</span>
              </div>
              <textarea
                key={doc.id}
                ref={editor}
                aria-label="Markdown 编辑器"
                spellCheck="false"
                value={doc.text}
                onChange={(e) => updateDoc({ text: e.target.value })}
                onMouseUp={() => selectedText("editor")}
                onKeyUp={(e) => {
                  if (e.shiftKey) selectedText("editor");
                }}
                onScroll={() =>
                  syncScroll(editor.current, preview.current, "editor")
                }
                onKeyDown={(e) => {
                  if (e.key === "Tab") {
                    e.preventDefault();
                    insert("  ");
                  }
                }}
              />
            </section>
          )}
          {config.mode !== "edit" && (
            <section className="preview-pane">
              <div className="reader-heading">
                <span>{config.mode === "read" ? "沉浸阅读" : "实时预览"}</span>
                <BookOpen size={14} />
              </div>
              <Preview
                text={doc.text}
                path={doc.path}
                dark={dark}
                innerRef={preview}
                onMouseUp={() => selectedText("preview")}
                onScroll={() =>
                  syncScroll(preview.current, editor.current, "preview")
                }
                onLink={handleLink}
              />
            </section>
          )}
          {selection && (
            <div className="selection-action">
              <span>{selection.text.length} 字已选中</span>
              <Button
                icon={Sparkles}
                className="primary"
                onMouseDown={(e) => e.preventDefault()}
                onClick={newConversation}
              >
                提问
              </Button>
              <Button
                icon={X}
                aria-label="取消选区"
                onClick={() => setSelection(null)}
              />
            </div>
          )}
        </main>
        {conversation && (
          <aside className="chat-panel">
            <div className="chat-title">
              <Sparkles size={17} />
              <strong>与文字对话</strong>
              <Button
                icon={X}
                title="收起对话"
                aria-label="收起对话"
                onClick={() => setChatID(null)}
              />
            </div>
            <div className="chat-profile">
              <span>{conversation.profile.name}</span>
              <small>{conversation.profile.model || "默认模型"}</small>
              <Button
                icon={Settings}
                title="智能体设置"
                onClick={() => setDialog("settings")}
              />
            </div>
            <blockquote className="reference">
              {conversation.reference.text}
              <small>
                {conversation.reference.line
                  ? `第 ${conversation.reference.line} 行 · `
                  : ""}
                {conversation.name}
              </small>
            </blockquote>
            <div className="messages">
              {conversation.messages.length ? (
                conversation.messages.map((m, i) => (
                  <div className={`message ${m.role}`} key={i}>
                    <small>
                      {m.role === "user" ? "你" : conversation.profile.name}
                    </small>
                    {m.role === "user" ? (
                      <p>{m.content}</p>
                    ) : (
                      <div
                        className="prose"
                        dangerouslySetInnerHTML={{
                          __html: renderMarkdown(
                            m.content || (conversation.busy ? "正在思考…" : ""),
                            null,
                          ),
                        }}
                      />
                    )}
                  </div>
                ))
              ) : (
                <div className="chat-empty">
                  <Sparkles size={28} />
                  <p>从这一段，开始新的思考。</p>
                  <small>引用内容会在发送时交给所选智能体。</small>
                  {["解释这段内容", "帮我改写得更清晰", "提炼核心观点"].map(
                    (text) => (
                      <button key={text} onClick={() => setQuestion(text)}>
                        {text}
                        <ChevronRight size={14} />
                      </button>
                    ),
                  )}
                </div>
              )}
              {conversation.error && (
                <div className="chat-error">
                  <AlertCircle size={15} />
                  {conversation.error}
                </div>
              )}
            </div>
            <div className="composer">
              <textarea
                placeholder="围绕这段文字提问…"
                aria-label="提问内容"
                value={question}
                onChange={(e) => setQuestion(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.ctrlKey && !e.shiftKey) {
                    e.preventDefault();
                    send();
                  }
                  if (e.key === "Enter" && e.ctrlKey) {
                    e.preventDefault();
                    setQuestion((q) => q + "\n");
                  }
                }}
              />
              <div>
                <small>Enter 发送 · Ctrl Enter 换行</small>
                {conversation.busy ? (
                  <Button
                    icon={Square}
                    aria-label="停止生成"
                    onClick={() => safely(() => api("agent-stop", chatID))}
                  />
                ) : (
                  <Button
                    icon={ArrowUp}
                    className="primary"
                    aria-label="发送提问"
                    disabled={!question.trim()}
                    onClick={send}
                  />
                )}
              </div>
            </div>
          </aside>
        )}
      </div>
      <footer className="status">
        <span>
          <Check size={13} />
          {dirty ? "草稿已自动保留 · 尚未保存到文件" : "已保存"}
          {doc.path && (
            <span className="status-path" title={doc.path}>
              {doc.path}
            </span>
          )}
        </span>
        <div>
          <button
            onClick={() =>
              safely(async () => {
                setHistory(await api("history", doc));
                setDialog("history");
              })
            }
          >
            <History size={13} />
            版本历史
          </button>
          <span>Markdown</span>
          <span className="accent">
            UTF-8 · {doc.text.includes("\r\n") ? "CRLF" : "LF"}
          </span>
          <span>{doc.text.replace(/\s/g, "").length} 字符</span>
          <span>{doc.text.split("\n").length} 行</span>
        </div>
        {focus && (
          <Button icon={ArrowLeft} onClick={() => setFocus(false)}>
            退出专注
          </Button>
        )}
      </footer>
      {notice && (
        <div className="toast" role="status">
          {notice}
        </div>
      )}
      {dialog === "settings" && (
        <SettingsDialog
          config={config}
          onChange={setConfig}
          safely={safely}
          toast={toast}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog === "commands" && (
        <Modal title="你想做什么？" onClose={() => setDialog(null)}>
          <div className="command-search">
            <Search size={18} />
            <input
              autoFocus
              placeholder="搜索命令…"
              aria-label="搜索命令"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>
          <div className="commands">
            {commands
              .filter(([label]) => label.includes(query))
              .map(([label, key, action]) => (
                <button
                  key={label}
                  onClick={() => {
                    setDialog(null);
                    action();
                  }}
                >
                  <span>{label}</span>
                  <kbd>{key}</kbd>
                </button>
              ))}
          </div>
        </Modal>
      )}
      {dialog === "export" && (
        <Modal title="导出文章" onClose={() => setDialog(null)}>
          <p className="modal-description">
            图表、公式和本地图片会随文章一起导出。
          </p>
          <div className="export-options">
            <Button
              icon={Code}
              onClick={() => {
                setDialog(null);
                exportDocument("html");
              }}
            >
              HTML · 独立网页
            </Button>
            <Button
              icon={FileText}
              onClick={() => {
                setDialog(null);
                exportDocument("pdf");
              }}
            >
              PDF · A4 文档
            </Button>
          </div>
        </Modal>
      )}
      {dialog === "history" && (
        <Modal title="本地版本历史" onClose={() => setDialog(null)} wide>
          <p className="modal-description">
            每次保存保留一份快照，最多 30 个版本。恢复后可检查并重新保存。
          </p>
          {history.length ? (
            <div className="history-list">
              {history.map((entry) => (
                <div key={entry.id}>
                  <div>
                    <strong>
                      {new Date(entry.date).toLocaleString("zh-CN")}
                    </strong>
                    <small>{entry.text.length} 字符</small>
                    <Button
                      onClick={() => {
                        updateDoc({ text: entry.text });
                        setDialog(null);
                        toast("已恢复到编辑器，保存后写入文件");
                      }}
                    >
                      恢复到编辑器
                    </Button>
                  </div>
                  <pre>{entry.text.slice(0, 400)}</pre>
                </div>
              ))}
            </div>
          ) : (
            <p className="empty">首次保存后，版本会出现在这里。</p>
          )}
        </Modal>
      )}
      {confirmClose && (
        <Modal
          title={
            confirmClose === "quit"
              ? "保留未保存的文字？"
              : "关闭未保存的文档？"
          }
          onClose={() => setConfirmClose(null)}
        >
          <p className="modal-description">
            {confirmClose === "quit"
              ? "可以保留草稿并退出，下次打开会恢复。草稿不会自动写入原文件。"
              : "保存到文件后关闭，或放弃这个标签中的更改。"}
          </p>
          <div className="dialog-actions">
            <Button onClick={() => setConfirmClose(null)}>取消</Button>
            {confirmClose === "quit" ? (
              <Button
                className="primary"
                onClick={() =>
                  safely(async () => {
                    await api(
                      "conversations-save",
                      current.current.conversations,
                    );
                    await api("quit-ready", session());
                  })
                }
              >
                保留草稿并退出
              </Button>
            ) : (
              <>
                <Button
                  onClick={() => {
                    removeTab(confirmClose);
                    setConfirmClose(null);
                  }}
                >
                  放弃更改
                </Button>
                <Button
                  className="primary"
                  onClick={async () => {
                    if (
                      await save(
                        false,
                        tabs.find((t) => t.id === confirmClose),
                      )
                    ) {
                      removeTab(confirmClose);
                      setConfirmClose(null);
                    }
                  }}
                >
                  保存并关闭
                </Button>
              </>
            )}
          </div>
        </Modal>
      )}
    </div>
  );
}
function SettingsDialog({ config, onChange, onClose, safely, toast }) {
  const [page, setPage] = useState("appearance");
  const [profileID, setProfileID] = useState(config.selectedAgent);
  const [token, setToken] = useState("");
  const [draft, setDraft] = useState(
    config.profiles.find((p) => p.id === profileID),
  );
  const patch = (value) => setDraft((d) => ({ ...d, ...value }));
  const saveProfile = () =>
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
  return (
    <Modal title="设置" onClose={onClose} wide>
      <div className="settings-layout">
        <nav>
          <button
            className={page === "appearance" ? "active" : ""}
            onClick={() => setPage("appearance")}
          >
            <Sun size={16} />
            外观与编辑
          </button>
          <button
            className={page === "agents" ? "active" : ""}
            onClick={() => setPage("agents")}
          >
            <Sparkles size={16} />
            智能体
          </button>
          <button
            className={page === "about" ? "active" : ""}
            onClick={() => setPage("about")}
          >
            <BookOpen size={16} />
            关于 Mirror
          </button>
        </nav>
        <div className="settings-content">
          {page === "appearance" && (
            <>
              <h3>让空间适合你的思考</h3>
              <p className="muted">设置自动保存，所有文档沿用同一视图模式。</p>
              <div className="field">
                主题
                <div className="theme-cards">
                  {[
                    ["light", Sun, "Mirror Light"],
                    ["dark", Moon, "Mirror Dark"],
                    ["system", Settings, "跟随系统"],
                  ].map(([id, Icon, text]) => (
                    <button
                      key={id}
                      className={config.theme === id ? "active" : ""}
                      onClick={() => onChange({ ...config, theme: id })}
                    >
                      <Icon size={22} />
                      <span>{text}</span>
                    </button>
                  ))}
                </div>
              </div>
              <label className="field">
                编辑器字号 <span>{config.fontSize} px</span>
                <input
                  type="range"
                  min="13"
                  max="24"
                  value={config.fontSize}
                  onChange={(e) =>
                    onChange({ ...config, fontSize: Number(e.target.value) })
                  }
                />
              </label>
              <div className="settings-note">
                <Check size={16} />
                <p>
                  草稿自动保留在本机。使用 Ctrl S 保存到原文件，Ctrl Shift S
                  另存为。
                </p>
              </div>
            </>
          )}
          {page === "agents" && (
            <>
              <h3>接着用你熟悉的 AI 工具</h3>
              <p className="muted">
                只有发送提问时，才会传递选区内容和当前对话。
              </p>
              <label className="field">
                连接配置
                <select
                  value={profileID}
                  onChange={(e) => {
                    const id = e.target.value;
                    setProfileID(id);
                    setDraft(config.profiles.find((p) => p.id === id));
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
              <label className="field">
                配置名称
                <input
                  value={draft.name}
                  onChange={(e) => patch({ name: e.target.value })}
                />
              </label>
              {draft.kind === "http" ? (
                <>
                  <label className="field">
                    基础地址（包含 /v1）
                    <input
                      placeholder="http://127.0.0.1:18789/v1"
                      value={draft.endpoint}
                      onChange={(e) => patch({ endpoint: e.target.value })}
                    />
                  </label>
                  <label className="field">
                    API Key / Bearer Token
                    <input
                      type="password"
                      autoComplete="off"
                      placeholder="留空保留现有密钥"
                      value={token}
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
                    placeholder={
                      draft.kind === "custom"
                        ? "C:\\Tools\\agent.exe"
                        : `${draft.kind}（留空自动查找 PATH）`
                    }
                    value={draft.executable}
                    onChange={(e) => patch({ executable: e.target.value })}
                  />
                </label>
              )}
              {draft.kind === "custom" ? (
                <label className="field">
                  参数（JSON 字符串数组）
                  <input
                    value={draft.arguments}
                    onChange={(e) => patch({ arguments: e.target.value })}
                  />
                </label>
              ) : (
                <label className="field">
                  模型 ID
                  <input
                    placeholder={
                      draft.kind === "http"
                        ? "必填，例如服务返回的模型 ID"
                        : "留空使用 CLI 默认模型"
                    }
                    value={draft.model}
                    onChange={(e) => patch({ model: e.target.value })}
                  />
                </label>
              )}
              {draft.kind === "codex" && (
                <label className="field">
                  思考深度
                  <select
                    value={draft.effort || ""}
                    onChange={(e) => patch({ effort: e.target.value })}
                  >
                    {["", "minimal", "low", "medium", "high", "xhigh"].map(
                      (value) => (
                        <option key={value} value={value}>
                          {value || "默认"}
                        </option>
                      ),
                    )}
                  </select>
                </label>
              )}
              <div className="settings-note">
                <AlertCircle size={16} />
                <p>
                  {draft.kind === "codex"
                    ? "需要已安装并登录 Codex CLI。首版每轮使用独立只读会话，携带 Mirror 中的对话上下文。"
                    : draft.kind === "claude"
                      ? "需要已安装并登录 Claude Code CLI。使用无工具的文字输出模式。"
                      : draft.kind === "http"
                        ? "兼容 /chat/completions 的流式或 JSON 服务；认证信息通过 Windows 系统加密保存。"
                        : "直接启动命令，不经过 shell。stdin 接收含 system、reference、messages 的 JSON，stdout 返回 UTF-8 文字。"}
                </p>
              </div>
              <Button className="primary" icon={Check} onClick={saveProfile}>
                保存并设为默认
              </Button>
              <p className="muted">
                已有对话沿用创建时的配置；更新后请重新选区开启对话。
              </p>
            </>
          )}
          {page === "about" && (
            <div className="about">
              <img src="./icon.png" alt="Mirror" />
              <h3>Mirror for Windows</h3>
              <p>0.1.0 · 写作、阅读与对话</p>
              <p className="muted">
                沿用 Mirror 的安静界面，在 Windows
                上让文字自然展开。文档、草稿、版本与对话都保留在本机。
              </p>
              <div className="settings-note">
                <p>
                  首版尚未迁移已有 Codex 会话引用、Smartwork 原生协议和
                  WorkBuddy Open API。兼容服务或包装命令可在智能体设置中接入。
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
createRoot(document.getElementById("root")).render(<App />);

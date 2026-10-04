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
  MoreHorizontal,
  Type,
  MoveHorizontal,
  Contrast,
  Share,
} from "lucide-react";
import { renderMarkdown, renderDiagrams, headings } from "./markdown";
import { disposeDiagrams } from "./diagrams";
import { version } from "../package.json";
import { syncSemanticScroll, editorLines } from "./scroll";
import { themes, selectedTheme, themeStyle } from "./themes";
import { Preferences, Typography, ThreadPicker } from "./preferences";
import { AnchoredLayer } from "./AnchoredLayer";
import {
  textareaSelectionAnchor,
  previewSelectionAnchor,
} from "./selection-anchor";
import {
  isMissing,
  selectableProfiles,
  defaultProfile,
} from "./agent-availability.mjs";
import hljs from "highlight.js/lib/common";
import "./style.css";
import "./native-parity.css";
const api = (name, ...args) => window.mirror.call(name, ...args);
const welcome = `# 让想法，在纸上展开\n\n一个安静的空间，容纳尚未成形的思考。\nMirror 把写作、阅读与对话放在同一张桌面上。\n\n## 从一张纸开始\n\n清晰的界面来自秩序：适度的留白、自然的层级，以及随手可用的工具。\n\n**把注意力留给内容**，让工具轻轻退到文字之后。\n\n> 写作不是把复杂的想法藏起来，而是给它一个可以展开的形状。\n\n### 今天想做的事\n\n- [x] 收集灵感，写下最初的几句话\n- [ ] 整理成一篇清晰的文章\n- [ ] 圈选一段内容，与 AI 讨论\n\n## 让结构自然浮现\n\n| 表达 | 方式 | 节奏 |\n| --- | --- | --- |\n| 草稿 | 自由记录 | 轻快 |\n| 阅读 | 梳理思路 | 从容 |\n| 对话 | 选中文字提问 | 深入 |\n\n### 从想法到文章\n\n\`\`\`mermaid\nflowchart LR\n  A[收集灵感] --> B[整理草稿]\n  B --> C[阅读与对话]\n  C --> D[分享文章]\n\`\`\`\n\n公式也可以离线显示：$E = mc^2$。\n\n---\n\n选中编辑器或预览中的文字，点击「提问」。在设置中连接你熟悉的智能体后，就能开始对话。\n`;
const memoriesForSaving = (values, settings) =>
  settings.memoryEnabled === false ? values.filter((c) => c.persisted) : values;
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
function Preview({
  text,
  path,
  dark,
  innerRef,
  onMouseUp,
  onScroll,
  onLink,
  memories = [],
  onMemory,
  preserveSingleLineBreaks,
}) {
  const ref = useRef();
  const html = React.useMemo(
    () => renderMarkdown(text, path, preserveSingleLineBreaks),
    [text, path, preserveSingleLineBreaks],
  );
  useEffect(() => {
    const article = ref.current;
    renderDiagrams(article, dark, true);
    return () => disposeDiagrams(article);
  }, [html, dark]);
  useEffect(() => {
    const article = ref.current;
    article.querySelectorAll(".memory-marker").forEach((node) => node.remove());
    for (const memory of memories) {
      const quote = memory.reference.text.trim().replace(/\s+/g, " ");
      const target = [...article.children].find(
        (node) =>
          quote && node.textContent.replace(/\s+/g, " ").includes(quote),
      );
      if (!target) continue;
      const button = document.createElement("button");
      button.className = "memory-marker";
      button.textContent = "◌";
      button.title = "打开此处对话";
      button.setAttribute("aria-label", "打开此处对话");
      button.dataset.memoryId = memory.id;
      button.onclick = () => onMemory(memory.id);
      target.style.position = "relative";
      target.appendChild(button);
    }
  }, [html, memories, onMemory]);
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
function Modal({ title, children, onClose, wide, className = "" }) {
  const ref = useRef();
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    const previous = document.activeElement;
    const root = ref.current;
    const focusable = () =>
      [
        ...root.querySelectorAll(
          'button, input, select, textarea, summary, [tabindex="0"]',
        ),
      ].filter((n) => !n.disabled && n.getClientRects().length);
    (
      root.querySelector('input:not([type="range"]):not([type="checkbox"])') ||
      focusable()[0]
    )?.focus();
    const key = (event) => {
      if ([...document.querySelectorAll(".modal")].at(-1) !== root) return;
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopImmediatePropagation();
        close.current();
      }
      if (event.key === "Tab") {
        const nodes = focusable();
        const i = nodes.indexOf(document.activeElement);
        if (!nodes.length) {
          event.preventDefault();
          return;
        }
        if (
          (event.shiftKey && i <= 0) ||
          (!event.shiftKey && (i < 0 || i === nodes.length - 1))
        ) {
          event.preventDefault();
          nodes[event.shiftKey ? nodes.length - 1 : 0].focus();
        }
      }
    };
    document.addEventListener("keydown", key, true);
    return () => {
      document.removeEventListener("keydown", key, true);
      if (previous?.isConnected) previous.focus();
    };
  }, []);
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <section
        className={`modal ${wide ? "wide" : ""} ${className}`}
        ref={ref}
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
function EditorDecorations({ areaRef, text, config, caretLine }) {
  const [layout, setLayout] = useState({ positions: [], scrollTop: 0 });
  React.useLayoutEffect(() => {
    const area = areaRef.current;
    if (!area || (!config.showLineNumbers && !config.highlightCurrentLine))
      return;
    const measure = () =>
      setLayout({ positions: editorLines(area), scrollTop: area.scrollTop });
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(area);
    const scroll = () =>
      setLayout((v) => ({ ...v, scrollTop: area.scrollTop }));
    area.addEventListener("scroll", scroll);
    return () => {
      observer.disconnect();
      area.removeEventListener("scroll", scroll);
    };
  }, [
    text,
    config.showLineNumbers,
    config.highlightCurrentLine,
    config.fontSize,
    config.wordWrap,
    config.editorFont,
    config.editorLineSpacing,
  ]);
  return (
    <>
      {config.highlightCurrentLine && (
        <div
          className="current-line"
          aria-hidden="true"
          style={{
            top: (layout.positions[caretLine] || 32) - layout.scrollTop,
          }}
        />
      )}
      {config.showLineNumbers && (
        <div className="line-numbers" aria-hidden="true">
          <div style={{ transform: `translateY(${-layout.scrollTop}px)` }}>
            {layout.positions.slice(0, -1).map((top, i) => (
              <div key={i} style={{ height: layout.positions[i + 1] - top }}>
                {i + 1}
              </div>
            ))}
          </div>
        </div>
      )}
    </>
  );
}
function ActionPopover({ title, children, anchor, onClose }) {
  const ref = useRef();
  const close = useRef(onClose);
  close.current = onClose;
  const [position, setPosition] = useState({
    left: Math.max(12, (anchor?.right || innerWidth - 120) - 250),
    top: (anchor?.bottom || 54) + 6,
  });
  React.useLayoutEffect(() => {
    const rect = ref.current.getBoundingClientRect();
    setPosition({
      left: Math.max(
        12,
        Math.min(
          innerWidth - rect.width - 12,
          (anchor?.right || innerWidth - 120) - rect.width,
        ),
      ),
      top: Math.max(
        12,
        Math.min(innerHeight - rect.height - 12, (anchor?.bottom || 54) + 6),
      ),
    });
    const previous = document.activeElement;
    ref.current.querySelector("button")?.focus();
    const outside = (e) => {
      if (!ref.current.contains(e.target)) close.current();
    };
    const key = (e) => {
      if (e.key === "Escape") {
        e.preventDefault();
        e.stopImmediatePropagation();
        close.current();
      }
      if (["ArrowDown", "ArrowUp", "Home", "End"].includes(e.key)) {
        e.preventDefault();
        const buttons = [...ref.current.querySelectorAll("button")].filter(
          (n) => !n.disabled,
        );
        const current = buttons.indexOf(document.activeElement);
        const next =
          e.key === "Home"
            ? 0
            : e.key === "End"
              ? buttons.length - 1
              : (current + (e.key === "ArrowDown" ? 1 : -1) + buttons.length) %
                buttons.length;
        buttons[next]?.focus();
      }
    };
    document.addEventListener("pointerdown", outside, true);
    document.addEventListener("keydown", key, true);
    return () => {
      document.removeEventListener("pointerdown", outside, true);
      document.removeEventListener("keydown", key, true);
      if (previous?.isConnected) previous.focus();
    };
  }, []);
  return (
    <section
      ref={ref}
      className="action-popover"
      role="dialog"
      aria-label={title}
      style={position}
    >
      {children}
    </section>
  );
}
function NavigationDrawer({ modal, title, onClose, children, width }) {
  return modal ? (
    <Modal title={title} onClose={onClose} wide>
      <div className="navigation-dialog">{children}</div>
    </Modal>
  ) : (
    <aside className="sidebar" style={{ width }}>
      {children}
    </aside>
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
  const previousDrawer = useRef("files");
  const [filter, setFilter] = useState("");
  const [focus, setFocus] = useState(false);
  const [dialog, setDialog] = useState(null);
  const [notice, setNotice] = useState("");
  const [selection, setSelection] = useState(null);
  const [conversations, setConversations] = useState([]);
  const [chatID, setChatID] = useState(null);
  const [chatAnchor, setChatAnchor] = useState(null);
  const [threadSource, setThreadSource] = useState(null);
  const [question, setQuestion] = useState("");
  const [history, setHistory] = useState([]);
  const [historyID, setHistoryID] = useState(null);
  const historyEntry =
    history.find((entry) => entry.id === historyID) || history[0];
  const [systemDark, setSystemDark] = useState(
    matchMedia("(prefers-color-scheme: dark)").matches,
  );
  const [query, setQuery] = useState("");
  const [confirmClose, setConfirmClose] = useState(null);
  const [searchScope, setSearchScope] = useState("document");
  const [workspaceResults, setWorkspaceResults] = useState([]);
  const [searchBusy, setSearchBusy] = useState(false);
  const [navigation, setNavigation] = useState(null);
  const [readingProgress, setReadingProgress] = useState(0);
  const syntax = useRef();
  const [discoveries, setDiscoveries] = useState([]);
  const [discovering, setDiscovering] = useState(true);
  const [settingsPage, setSettingsPage] = useState("agents");
  const [readerMenu, setReaderMenu] = useState(null);
  const [menuAnchor, setMenuAnchor] = useState(null);
  const showMenu = (event, name) => {
    const rect = event.currentTarget.getBoundingClientRect();
    setMenuAnchor({ right: rect.right, bottom: rect.bottom });
    setDialog(name);
  };
  const [caretLine, setCaretLine] = useState(0);
  const availableAgents = selectableProfiles(config.profiles, discoveries);
  const openSettings = (page = "agents") => {
    setSettingsPage(page);
    setDialog("settings");
  };
  const [chatOptions, setChatOptions] = useState(false);
  const [chatModels, setChatModels] = useState([]);
  const codexProfile = availableAgents.find(
    (p) => p.kind === "codex" && (!p.connection || p.connection === "native"),
  );
  const editor = useRef();
  const preview = useRef();
  const workspace = useRef();
  const openMemory = useCallback((id) => {
    const viewport = preview.current;
    setChatAnchor({
      element: viewport,
      preferred: "right",
      getRect: () =>
        viewport
          ?.querySelector(`[data-memory-id="${CSS.escape(id)}"]`)
          ?.getBoundingClientRect(),
    });
    setChatID(id);
  }, []);
  const current = useRef();
  const scrollSource = useRef(null);
  const pendingDraft = useRef();
  const doc = tabs.find((tab) => tab.id === active) || tabs[0];
  const theme = selectedTheme(config, systemDark);
  const dark = theme.dark;
  const conversation = conversations.find((value) => value.id === chatID);
  const outline = headings(doc?.text || "");
  const dirty = doc && doc.text !== doc.savedText;
  current.current = { tabs, active, folder, config, conversations, ready };
  const toast = useCallback((text) => setNotice(text), []);
  useEffect(() => {
    const area = editor.current,
      layer = syntax.current;
    if (!area || !layer) return;
    const align = () => {
      layer.style.width = `${area.clientWidth}px`;
      layer.scrollTop = area.scrollTop;
      layer.scrollLeft = area.scrollLeft;
    };
    align();
    const observer = new ResizeObserver(align);
    observer.observe(area);
    return () => observer.disconnect();
  }, [doc?.id, config.mode, config.fontSize, ready]);
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
          persisted: true,
          busy: false,
          needsRefresh: !!c.threadId && (c.needsRefresh || c.busy),
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
          await api(
            "conversations-save",
            memoriesForSaving(
              current.current.conversations,
              current.current.config,
            ),
          );
          await api("settings-save", current.current.config);
          await api("quit-ready", session());
        });
    });
    const offDocument = window.mirror.on("document-changed", (fresh) => {
      setTabs((values) =>
        values.map((tab) => {
          if (
            tab.path !== fresh.path ||
            (tab.stamp === fresh.stamp && !fresh.missing)
          )
            return tab;
          if (!fresh.missing && fresh.text === tab.text)
            return {
              ...tab,
              stamp: fresh.stamp,
              savedText: fresh.text,
              external: null,
            };
          if (!fresh.missing && tab.text === tab.savedText)
            return { ...tab, ...fresh, savedText: fresh.text, external: null };
          return { ...tab, external: fresh };
        }),
      );
    });
    const offFolder = window.mirror.on("folder-changed", (value) =>
      setFolder((previous) =>
        previous?.root === value.root
          ? { ...previous, files: value.files }
          : previous,
      ),
    );
    const offFolderOpened = window.mirror.on("folder-opened", (value) => {
      setFolder(value);
      setSidebar("files");
    });
    const offError = window.mirror.on("document-error", toast);
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
            needsRefresh: !!c.threadId && event.type !== "delta",
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
      offDocument();
      offFolder();
      offFolderOpened();
      offError();
    };
  }, []);
  useEffect(() => {
    if (!ready) return;
    let live = true;
    setDiscovering(true);
    api("agent-discover", config.profiles)
      .then((rows) => {
        if (live) setDiscoveries(rows);
      })
      .catch(() => {
        // A failed scan must not discard configured connections.
        if (live) setDiscoveries([]);
      })
      .finally(() => {
        if (live) setDiscovering(false);
      });
    return () => {
      live = false;
    };
  }, [ready, config.profiles, dialog === "settings", !!chatID]);
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
      (config.autosaveDelay || 0.5) * 1000,
    );
    return () => clearTimeout(timer);
  }, [tabs, active, folder, ready, config.autosaveDelay]);
  useEffect(() => {
    if (
      sidebar !== "search" ||
      searchScope !== "workspace" ||
      !folder ||
      !filter.trim()
    ) {
      setWorkspaceResults([]);
      setSearchBusy(false);
      return;
    }
    let live = true;
    setSearchBusy(true);
    const timer = setTimeout(
      () =>
        safely(async () => {
          try {
            const matches = await api("workspace-search", filter);
            if (live) setWorkspaceResults(matches);
          } finally {
            if (live) setSearchBusy(false);
          }
        }),
      500,
    );
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [filter, sidebar, searchScope, folder?.root]);
  useEffect(() => {
    if (!navigation || navigation.path !== doc?.path) return;
    const timer = setTimeout(() => {
      if (navigation.line != null) jump({ line: navigation.line });
      else if (navigation.fragment) {
        const node = preview.current?.querySelector(
          `[id="${CSS.escape(navigation.fragment)}"]`,
        );
        node?.scrollIntoView({ block: "start" });
      } else {
        if (editor.current) editor.current.scrollTop = 0;
        if (preview.current) preview.current.scrollTop = 0;
      }
      setNavigation(null);
    }, 50);
    return () => clearTimeout(timer);
  }, [navigation, doc?.id, config.mode]);
  useEffect(() => {
    if (ready) safely(() => api("settings-save", config));
  }, [config, ready]);
  useEffect(() => {
    if (!ready) return;
    const timer = setTimeout(
      () =>
        safely(() =>
          api("conversations-save", memoriesForSaving(conversations, config)),
        ),
      400,
    );
    return () => clearTimeout(timer);
  }, [conversations, ready, config.memoryEnabled]);
  useEffect(() => {
    if (
      config.memoryEnabled !== false &&
      conversations.some((c) => !c.persisted)
    ) {
      setConversations((values) =>
        values.map((c) => ({ ...c, persisted: true })),
      );
    }
  }, [config.memoryEnabled, conversations]);
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
            ? { ...tab, ...result, savedText: target.text, external: null }
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
    let anchor;
    if (!doc) return;
    if (source === "editor") {
      if (!editor.current) return;
      start = editor.current.selectionStart;
      end = editor.current.selectionEnd;
      text = doc.text.slice(start, end);
      anchor = textareaSelectionAnchor(editor.current);
    } else {
      const range = window.getSelection();
      anchor = previewSelectionAnchor(range, preview.current);
      text = anchor ? range.toString() : "";
    }
    if (text.trim() && anchor)
      setSelection({
        anchor,
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
  useEffect(() => {
    let frame;
    const update = () => {
      if (
        dialog ||
        document.activeElement?.closest(
          ".selection-action, .chat-panel, .modal, .action-popover",
        )
      )
        return;
      selectedText(
        document.activeElement === editor.current ? "editor" : "preview",
      );
    };
    const schedule = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(update);
    };
    document.addEventListener("selectionchange", schedule);
    return () => {
      cancelAnimationFrame(frame);
      document.removeEventListener("selectionchange", schedule);
    };
  }, [doc?.id, doc?.text, config.mode, dialog]);
  const newConversation = () => {
    if (!selection) return;
    if (discovering) {
      toast("正在检测智能体，请稍候…");
      return;
    }
    const profile = defaultProfile(
      config.profiles,
      discoveries,
      config.selectedAgent,
    );
    if (!profile) {
      openSettings();
      toast("未检测到可用智能体，请先配置连接。");
      return;
    }
    const c = {
      id: crypto.randomUUID(),
      persisted: config.memoryEnabled !== false,
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
    setChatAnchor(selection.anchor);
    setChatID(c.id);
    setQuestion("");
    setSelection(null);
  };
  const send = () =>
    safely(async () => {
      if (
        !question.trim() ||
        !conversation ||
        conversation.busy ||
        conversation.needsRefresh ||
        isMissing(conversation.profile, discoveries)
      )
        return;
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
          threadId: conversation.threadId,
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
      host.innerHTML = renderMarkdown(
        doc.text,
        doc.path,
        config.preserveSingleLineBreaks,
      );
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
    syncSemanticScroll(source, target, name, config.scrollSync || "smart");
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
      editor.current.scrollTop = editorLines(editor.current)[heading.line] || 0;
    }
    const nodes = [
      ...(preview.current?.querySelectorAll("[data-source-line]") || []),
    ];
    const target =
      nodes.find((node) => +node.dataset.sourceLine === heading.line) ||
      nodes.filter((node) => +node.dataset.sourceLine <= heading.line).at(-1);
    target?.scrollIntoView({ behavior: "smooth", block: "start" });
  };
  const handleLink = (value) => {
    if (value?.startsWith("#")) {
      const id = value.slice(1);
      const node = [...(preview.current?.querySelectorAll("[id]") || [])].find(
        (node) => node.id === id || node.id === decodeURIComponent(id),
      );
      if (node) {
        node.scrollIntoView({ block: "start", behavior: "smooth" });
        return;
      }
      const target = decodeURIComponent(id).replace(/-/g, " ").toLowerCase();
      const h = outline.find((h) => h.text.toLowerCase() === target);
      if (h) jump(h);
    } else if (/^https?:/i.test(value || ""))
      safely(() => api("external", value));
    else if (doc.path)
      safely(async () => {
        const file = await api("link-open", doc.path, value);
        addOpened(file);
        setNavigation({ path: file.path, fragment: file.fragment });
      });
    else toast("请先保存当前文档，再打开相对链接。");
  };
  useEffect(() => {
    const key = (event) => {
      if (event.key === "Escape") {
        setDialog(null);
        setReaderMenu(null);
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
      style={{
        ...themeStyle(theme),
        "--source-ratio": `${config.sourceRatio || 50}%`,
        "--tab-width": config.tabWidth || 2,
        "--editor-size": `${config.fontSize}px`,
        "--editor-font":
          config.editorFont || "Consolas, 'Microsoft YaHei UI', monospace",
        "--code-font": config.codeFont || "Consolas, monospace",
        "--editor-line-height": `${config.fontSize * 1.5 + (config.editorLineSpacing ?? 6)}px`,
        "--preview-size": `${config.previewSize || 17}px`,
        "--preview-line-height": config.lineHeight || 1.88,
        "--content-width": `${config.contentWidth || 720}px`,
        "--preview-font":
          config.readingFont || 'Georgia, "Noto Serif CJK SC", SimSun, serif',
      }}
    >
      <header className="topbar">
        <div className="brand">
          <img src="./icon.png" alt="" />
          <strong>Mirror</strong>
        </div>
        <div className="title-document">
          <strong>
            {doc.name.replace(/\.(md|markdown)$/i, "")}
            {dirty && <span className="dirty-dot" />}
          </strong>
          <small>
            {doc.path?.split(/[\\/]/).slice(-2, -1)[0] || "尚未保存"}
          </small>
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
            icon={Search}
            title="快速打开 (Ctrl O)"
            aria-label="快速打开"
            onClick={() => {
              setQuery("");
              setDialog("quick-open");
            }}
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
            icon={Share}
            title="导出"
            aria-label="导出"
            onClick={(event) => showMenu(event, "export")}
          />
          <Button
            icon={MoreHorizontal}
            aria-label="更多操作"
            title="更多操作"
            onClick={(event) => showMenu(event, "more")}
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
            ].map(([id, Icon, label]) => (
              <button
                key={id}
                className={sidebar === id && id !== "search" ? "active" : ""}
                onClick={() => {
                  if (id === "search") {
                    previousDrawer.current =
                      sidebar === "search" ? previousDrawer.current : sidebar;
                    setSidebar("search");
                  } else setSidebar(sidebar === id ? null : id);
                }}
              >
                <Icon size={21} strokeWidth={1.6} />
                <span>{label}</span>
              </button>
            ))}
            <div className="rail-bottom">
              <button onClick={() => openSettings()}>
                <Settings size={21} strokeWidth={1.6} />
                <span>设置</span>
              </button>
            </div>
          </nav>
        )}
        {!focus && sidebar && (
          <NavigationDrawer
            modal={sidebar === "search"}
            title={searchScope === "workspace" ? "工作区搜索" : "文内查找"}
            onClose={() => setSidebar(previousDrawer.current)}
            width={config.sidebarWidth || 252}
          >
            <div
              className="sidebar-resizer"
              role="separator"
              aria-label="调整侧栏宽度"
              aria-orientation="vertical"
              onPointerDown={(event) => {
                event.currentTarget.setPointerCapture(event.pointerId);
              }}
              onPointerMove={(event) => {
                if (event.currentTarget.hasPointerCapture(event.pointerId)) {
                  const left =
                    event.currentTarget.parentElement.getBoundingClientRect()
                      .left;
                  setConfig((c) => ({
                    ...c,
                    sidebarWidth: Math.max(
                      210,
                      Math.min(420, event.clientX - left),
                    ),
                  }));
                }
              }}
            />
            <div className="sidebar-title">
              <div>
                <small>
                  {sidebar === "files"
                    ? "WORKSPACE"
                    : sidebar === "outline"
                      ? "CONTENTS"
                      : sidebar === "chats"
                        ? "CONVERSATIONS"
                        : searchScope === "workspace"
                          ? "SEARCH WORKSPACE"
                          : "FIND IN DOCUMENT"}
                </small>
                <h3>
                  {sidebar === "files"
                    ? folder?.name || "本地文档"
                    : sidebar === "outline"
                      ? "文章大纲"
                      : sidebar === "chats"
                        ? "选区对话"
                        : searchScope === "workspace"
                          ? "工作区搜索"
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
                {config.mode === "read" && (
                  <div className="reading-progress">
                    <span>阅读进度</span>
                    <strong>{readingProgress}%</strong>
                    <progress max="100" value={readingProgress} />
                  </div>
                )}
              </div>
            )}
            {sidebar === "search" && (
              <>
                <div className="search-scope">
                  <button
                    className={searchScope === "document" ? "active" : ""}
                    onClick={() => setSearchScope("document")}
                  >
                    当前文档
                  </button>
                  <button
                    disabled={!folder}
                    className={searchScope === "workspace" ? "active" : ""}
                    onClick={() => setSearchScope("workspace")}
                  >
                    整个工作区
                  </button>
                </div>
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
                  {searchBusy && <p className="empty">正在搜索…</p>}
                  {searchScope === "workspace" &&
                    workspaceResults.map((match, index) => (
                      <button
                        key={index}
                        onClick={() =>
                          safely(async () => {
                            addOpened(await api("open", match.path));
                            setNavigation({
                              path: match.path,
                              line: match.line,
                            });
                          })
                        }
                      >
                        <small>
                          {match.relative} · 第 {match.line + 1} 行
                        </small>
                        <span>{match.text}</span>
                      </button>
                    ))}
                  {searchScope === "document" &&
                    filter &&
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
                          setChatAnchor(null);
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
          </NavigationDrawer>
        )}
        <main
          ref={workspace}
          className={`workspace mode-${focus && config.mode === "split" ? "edit" : config.mode}`}
        >
          <div className="workspace-progress" aria-hidden="true">
            <span style={{ width: `${readingProgress}%` }} />
          </div>
          {doc.external && (
            <div className="conflict-banner" role="alert">
              <AlertCircle size={16} />
              <span>
                {doc.external.missing
                  ? "磁盘文件已被删除。编辑内容仍保留。"
                  : "磁盘文件已在其他程序中修改。编辑内容仍保留。"}
              </span>
              {!doc.external.missing && (
                <Button
                  onClick={() =>
                    updateDoc({
                      ...doc.external,
                      savedText: doc.external.text,
                      external: null,
                    })
                  }
                >
                  重新载入磁盘版本
                </Button>
              )}
              <Button onClick={() => save(true)}>另存为</Button>
            </div>
          )}
          {config.mode !== "read" && (
            <section
              className="editor-pane"
              style={
                config.mode === "split" && !focus
                  ? { flex: `0 0 calc(${config.sourceRatio || 50}% - 28px)` }
                  : undefined
              }
            >
              <div className="pane-title">
                <span>MARKDOWN</span>
                <details className="format-menu">
                  <summary aria-label="格式工具" title="格式工具">
                    <Type size={13} />
                  </summary>
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
                </details>
                <span className="source-label">Source</span>
              </div>
              <div
                className={`source-body ${config.showLineNumbers ? "with-line-numbers" : ""}`}
                style={{
                  "--wrap": config.wordWrap === false ? "pre" : "pre-wrap",
                }}
              >
                <EditorDecorations
                  areaRef={editor}
                  text={doc.text}
                  config={config}
                  caretLine={caretLine}
                />
                <pre className="syntax-layer" ref={syntax} aria-hidden="true">
                  <code
                    dangerouslySetInnerHTML={{
                      __html:
                        doc.text.length < 200000
                          ? hljs.highlight(doc.text + "\n", {
                              language: "markdown",
                            }).value
                          : doc.text
                              .replace(/&/g, "&amp;")
                              .replace(/</g, "&lt;") + "\n",
                    }}
                  />
                </pre>
                <textarea
                  key={doc.id}
                  ref={editor}
                  aria-label="Markdown 编辑器"
                  placeholder="开始用 Markdown 写作…"
                  onSelect={(e) =>
                    setCaretLine(
                      e.target.value
                        .slice(0, e.target.selectionStart)
                        .split("\n").length - 1,
                    )
                  }
                  spellCheck={!!config.spellCheck}
                  wrap={config.wordWrap === false ? "off" : "soft"}
                  value={doc.text}
                  onChange={(e) => {
                    updateDoc({ text: e.target.value });
                    if (config.typewriter) {
                      const line =
                        e.target.value
                          .slice(0, e.target.selectionStart)
                          .split("\n").length - 1;
                      e.target.scrollTop = Math.max(
                        0,
                        (editorLines(e.target)[line] || 0) -
                          e.target.clientHeight / 2,
                      );
                    }
                  }}
                  onMouseUp={() => selectedText("editor")}
                  onFocus={() => selectedText("editor")}
                  onKeyUp={(e) => {
                    if (e.shiftKey) selectedText("editor");
                  }}
                  onScroll={() => {
                    if (syntax.current) {
                      syntax.current.scrollTop = editor.current.scrollTop;
                      syntax.current.scrollLeft = editor.current.scrollLeft;
                    }
                    syncScroll(editor.current, preview.current, "editor");
                  }}
                  onKeyDown={(e) => {
                    if (
                      config.autoPair &&
                      !e.ctrlKey &&
                      !e.altKey &&
                      !e.metaKey &&
                      ["(", "[", "{", '"', "'"].includes(e.key)
                    ) {
                      e.preventDefault();
                      insert(
                        e.key,
                        { "(": ")", "[": "]", "{": "}", '"': '"', "'": "'" }[
                          e.key
                        ],
                      );
                    }
                    if (e.key === "Tab") {
                      e.preventDefault();
                      insert(" ".repeat(config.tabWidth || 2));
                    }
                  }}
                />
              </div>
            </section>
          )}
          {config.mode === "split" && !focus && (
            <div
              className="workspace-resizer"
              role="separator"
              aria-label="调整分栏宽度"
              aria-orientation="vertical"
              onPointerDown={(e) =>
                e.currentTarget.setPointerCapture(e.pointerId)
              }
              onPointerMove={(e) => {
                if (!e.currentTarget.hasPointerCapture(e.pointerId)) return;
                const rect =
                  e.currentTarget.parentElement.getBoundingClientRect();
                setConfig((c) => ({
                  ...c,
                  sourceRatio: Math.max(
                    25,
                    Math.min(75, ((e.clientX - rect.left) / rect.width) * 100),
                  ),
                }));
              }}
            />
          )}
          {config.mode !== "edit" && !(focus && config.mode === "split") && (
            <section className="preview-pane">
              <div className="reader-heading">
                <span>{config.mode === "read" ? "沉浸阅读" : "实时预览"}</span>
                <BookOpen size={14} />
              </div>
              <Preview
                text={doc.text}
                preserveSingleLineBreaks={config.preserveSingleLineBreaks}
                path={doc.path}
                dark={dark}
                innerRef={preview}
                onMouseUp={() => selectedText("preview")}
                onScroll={() => {
                  setReadingProgress(
                    Math.round(
                      (100 * preview.current.scrollTop) /
                        Math.max(
                          1,
                          preview.current.scrollHeight -
                            preview.current.clientHeight,
                        ),
                    ),
                  );
                  syncScroll(preview.current, editor.current, "preview");
                }}
                onLink={handleLink}
                memories={(config.memoryEnabled === false
                  ? []
                  : conversations
                ).filter(
                  (c) => c.docID === doc.id || (c.path && c.path === doc.path),
                )}
                onMemory={openMemory}
              />
            </section>
          )}
          {config.mode === "read" && (
            <nav className="reader-tools" aria-label="阅读工具">
              <Button
                icon={Type}
                title="阅读排版"
                aria-label="阅读排版"
                onClick={() => setDialog("typography")}
              />
              <Button
                icon={MoveHorizontal}
                title="切换阅读宽度"
                aria-label="切换阅读宽度"
                onClick={() =>
                  setReaderMenu(readerMenu === "width" ? null : "width")
                }
              />
              <Button
                icon={Contrast}
                title="阅读主题"
                aria-label="阅读主题"
                onClick={() =>
                  setReaderMenu(readerMenu === "theme" ? null : "theme")
                }
              />
              <Button
                icon={Focus}
                title="专注阅读"
                className={focus ? "active" : ""}
                aria-label="专注阅读"
                onClick={() => setFocus(!focus)}
              />
              <Button
                icon={Share}
                title="导出文档"
                aria-label="阅读导出"
                onClick={(event) => showMenu(event, "export")}
              />
              {readerMenu && (
                <div className="reader-menu" role="menu">
                  {readerMenu === "width"
                    ? [
                        [620, "窄"],
                        [760, "标准"],
                        [900, "宽"],
                      ].map(([width, label]) => (
                        <button
                          key={width}
                          role="menuitemradio"
                          aria-checked={config.contentWidth === width}
                          onClick={() => {
                            setConfig((c) => ({ ...c, contentWidth: width }));
                            setReaderMenu(null);
                          }}
                        >
                          {label}
                          {config.contentWidth === width && <Check size={12} />}
                        </button>
                      ))
                    : [...themes, ...(config.customThemes || [])].map((t) => (
                        <button
                          key={t.id}
                          role="menuitemradio"
                          aria-checked={config.theme === t.id}
                          onClick={() => {
                            setConfig((c) => ({ ...c, theme: t.id }));
                            setReaderMenu(null);
                          }}
                        >
                          {t.name}
                          {config.theme === t.id && <Check size={12} />}
                        </button>
                      ))}
                </div>
              )}
            </nav>
          )}
          {selection && (
            <AnchoredLayer
              anchor={selection.anchor}
              boundaryRef={workspace}
              hideOffscreen
              className="selection-action"
              onMouseDown={(e) => e.preventDefault()}
            >
              <Button
                icon={Sparkles}
                className="primary"
                onMouseDown={(e) => e.preventDefault()}
                onClick={newConversation}
              >
                提问
              </Button>
            </AnchoredLayer>
          )}
        </main>
        {conversation && (
          <AnchoredLayer
            as="aside"
            anchor={chatAnchor}
            boundaryRef={workspace}
            maxHeight={560}
            className="chat-panel"
            role="dialog"
            aria-label="引用对话"
          >
            <div className="chat-title">
              <button
                onClick={() => setChatOptions(!chatOptions)}
                title="切换智能体与模型"
              >
                {conversation.profile.name}
                <ChevronDown size={12} />
              </button>
              <small>{conversation.profile.model || "默认模型"}</small>
              <Button
                icon={Settings}
                aria-label="智能体设置"
                title="智能体设置"
                onClick={() => openSettings()}
              />
              <Button
                icon={Trash2}
                aria-label="删除气泡记录"
                title="删除气泡记录"
                disabled={conversation.busy}
                onClick={() => {
                  setConversations((values) =>
                    values.filter((c) => c.id !== chatID),
                  );
                  setChatID(null);
                }}
              />
              <Button
                icon={X}
                title="收起对话"
                aria-label="收起对话"
                onClick={() => setChatID(null)}
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
                  <p>问问这段内容…</p>
                </div>
              )}
              {isMissing(conversation.profile, discoveries) && (
                <div className="chat-error">
                  此智能体未安装或命令路径已失效。历史对话已保留。
                  <Button onClick={() => openSettings()}>配置智能体</Button>
                </div>
              )}
              {conversation.error && (
                <div className="chat-error">
                  <AlertCircle size={15} />
                  {conversation.error}
                </div>
              )}
            </div>
            {chatOptions && (
              <div className="chat-options">
                {codexProfile && (
                  <Button
                    disabled={conversation.busy}
                    onClick={() => {
                      setThreadSource({ ...conversation, anchor: chatAnchor });
                      setChatOptions(false);
                      setDialog("codex-threads");
                    }}
                  >
                    引用到 Codex 会话…
                  </Button>
                )}
                <label>
                  智能体
                  <select
                    value={conversation.profile.id}
                    disabled={conversation.busy || !!conversation.threadId}
                    onChange={(e) => {
                      const profile = config.profiles.find(
                        (p) => p.id === e.target.value,
                      );
                      const c = {
                        ...conversation,
                        id: crypto.randomUUID(),
                        persisted: config.memoryEnabled !== false,
                        profile: { ...profile },
                        messages: [],
                        busy: false,
                        error: null,
                        date: new Date().toISOString(),
                      };
                      setConversations((values) => [...values, c]);
                      setChatID(c.id);
                      setConfig((v) => ({ ...v, selectedAgent: profile.id }));
                    }}
                  >
                    {!availableAgents.some(
                      (p) => p.id === conversation.profile.id,
                    ) && (
                      <option value={conversation.profile.id} disabled>
                        {conversation.profile.name} · 不可用
                      </option>
                    )}
                    {availableAgents.map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  模型
                  <input
                    list="chat-model-options"
                    value={conversation.profile.model || ""}
                    disabled={conversation.busy || !!conversation.threadId}
                    placeholder="默认模型"
                    onChange={(e) => {
                      const c = {
                        ...conversation,
                        id: crypto.randomUUID(),
                        persisted: config.memoryEnabled !== false,
                        profile: {
                          ...conversation.profile,
                          model: e.target.value,
                        },
                        messages: [],
                        busy: false,
                        error: null,
                        date: new Date().toISOString(),
                      };
                      if (!conversation.messages.length)
                        setConversations((values) =>
                          values.map((v) =>
                            v.id === conversation.id
                              ? { ...v, profile: c.profile }
                              : v,
                          ),
                        );
                      else {
                        setConversations((values) => [...values, c]);
                        setChatID(c.id);
                      }
                    }}
                  />
                </label>
                <Button
                  onClick={() =>
                    safely(async () => {
                      const models = await api(
                        "agent-models",
                        conversation.profile,
                      );
                      setChatModels(models);
                      if (!models.length) toast("可手动填写模型 ID");
                    })
                  }
                >
                  模型列表
                </Button>
                <datalist id="chat-model-options">
                  {chatModels.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.name}
                    </option>
                  ))}
                </datalist>
                <label>
                  思考深度
                  <select
                    disabled={conversation.busy || !!conversation.threadId}
                    value={conversation.profile.effort || ""}
                    onChange={(e) => {
                      const profile = {
                        ...conversation.profile,
                        effort: e.target.value,
                      };
                      if (!conversation.messages.length)
                        setConversations((values) =>
                          values.map((c) =>
                            c.id === conversation.id ? { ...c, profile } : c,
                          ),
                        );
                      else {
                        const c = {
                          ...conversation,
                          id: crypto.randomUUID(),
                          persisted: config.memoryEnabled !== false,
                          profile,
                          messages: [],
                          date: new Date().toISOString(),
                          error: null,
                        };
                        setConversations((values) => [...values, c]);
                        setChatID(c.id);
                      }
                    }}
                  >
                    {(conversation.profile.kind === "codex"
                      ? [
                          "",
                          "none",
                          "minimal",
                          "low",
                          "medium",
                          "high",
                          "xhigh",
                        ]
                      : conversation.profile.kind === "claude"
                        ? ["", "low", "medium", "high", "xhigh", "max"]
                        : conversation.profile.kind === "pi"
                          ? [
                              "",
                              "off",
                              "minimal",
                              "low",
                              "medium",
                              "high",
                              "xhigh",
                              "max",
                            ]
                          : [""]
                    ).map((effort) => (
                      <option key={effort} value={effort}>
                        {effort || "默认"}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
            )}
            {conversation.threadId && (
              <div className="thread-refresh">
                <Button
                  disabled={conversation.busy}
                  onClick={() =>
                    safely(async () => {
                      const result = await api(
                        "codex-history",
                        conversation.profile,
                        conversation.threadId,
                      );
                      setConversations((values) =>
                        values.map((c) =>
                          c.id === chatID
                            ? {
                                ...c,
                                messages: result.messages,
                                needsRefresh: false,
                                error: null,
                              }
                            : c,
                        ),
                      );
                    })
                  }
                >
                  刷新原会话历史
                </Button>
                <Button
                  onClick={() =>
                    safely(async () => {
                      await api("codex-copy", conversation.reference);
                      toast("引用已复制，可粘贴到 Codex");
                    })
                  }
                >
                  复制引用到 Codex
                </Button>
              </div>
            )}
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
                    disabled={
                      !question.trim() ||
                      conversation.needsRefresh ||
                      isMissing(conversation.profile, discoveries)
                    }
                    onClick={send}
                  />
                )}
              </div>
            </div>
          </AnchoredLayer>
        )}
      </div>
      {!focus && (
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
        </footer>
      )}
      {focus && config.mode !== "read" && (
        <Button
          className="focus-exit"
          icon={ArrowLeft}
          onClick={() => setFocus(false)}
        >
          退出专注
        </Button>
      )}
      {notice && (
        <div className="toast" role="status">
          {notice}
        </div>
      )}
      {dialog === "settings" && (
        <Preferences
          Modal={Modal}
          Button={Button}
          config={config}
          initialPage={settingsPage}
          discoveries={discoveries}
          onDiscover={setDiscoveries}
          conversations={conversations}
          onConversationsChange={setConversations}
          onChange={setConfig}
          safely={safely}
          toast={toast}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog === "codex-threads" && codexProfile && threadSource && (
        <ThreadPicker
          profile={codexProfile}
          Modal={Modal}
          Button={Button}
          safely={safely}
          onClose={() => setDialog(null)}
          onSelect={(thread, messages) => {
            const c = {
              id: threadSource.messages.length
                ? crypto.randomUUID()
                : threadSource.id,
              persisted: config.memoryEnabled !== false,
              docID: threadSource.docID,
              path: threadSource.path,
              name: thread.name || thread.preview || threadSource.name,
              reference: { ...threadSource.reference },
              profile: { ...codexProfile },
              threadId: thread.id,
              messages,
              date: new Date().toISOString(),
              busy: false,
            };
            setConversations((values) =>
              values.some((value) => value.id === c.id)
                ? values.map((value) => (value.id === c.id ? c : value))
                : [...values, c],
            );
            setChatAnchor(threadSource.anchor);
            setChatID(c.id);
            setSelection(null);
            setDialog(null);
            setQuestion("");
          }}
        />
      )}
      {dialog === "typography" && (
        <Modal title="阅读排版" onClose={() => setDialog(null)}>
          <Typography config={config} onChange={setConfig} />
        </Modal>
      )}
      {dialog === "quick-open" && (
        <Modal title="快速打开" onClose={() => setDialog(null)}>
          <div className="command-search">
            <Search size={18} />
            <input
              autoFocus
              aria-label="快速打开文件"
              placeholder="搜索工作区或最近文件…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>
          <div className="commands">
            {[
              ...new Set([
                ...(folder?.files || []).map((f) => f.path),
                ...recent,
              ]),
            ]
              .filter((file) =>
                file.toLowerCase().includes(query.toLowerCase()),
              )
              .map((file) => (
                <button
                  key={file}
                  onClick={() => {
                    setDialog(null);
                    safely(async () => addOpened(await api("open", file)));
                  }}
                >
                  <FileText size={14} />
                  <span>{file.split(/[\\/]/).pop()}</span>
                  <small title={file}>{file}</small>
                </button>
              ))}
          </div>
          <Button
            icon={FolderOpen}
            onClick={() => {
              setDialog(null);
              openFile();
            }}
          >
            打开文件…
          </Button>
        </Modal>
      )}
      {dialog === "more" && (
        <ActionPopover
          title="更多操作"
          anchor={menuAnchor}
          onClose={() => setDialog(null)}
        >
          <div className="commands">
            {commands.map(([label, key, action]) => (
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
            <button
              onClick={() => {
                setDialog(null);
                setSidebar("chats");
              }}
            >
              <span>对话</span>
              <MessageSquare size={14} />
            </button>
          </div>
        </ActionPopover>
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
        <ActionPopover
          title="导出文章"
          anchor={menuAnchor}
          onClose={() => setDialog(null)}
        >
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
        </ActionPopover>
      )}
      {dialog === "history" && (
        <Modal
          title="本地版本历史"
          onClose={() => setDialog(null)}
          wide
          className="history-modal"
        >
          <p className="modal-description">
            {doc.name} · 每次保存保留一份快照，最多 30 个版本。
          </p>
          {historyEntry ? (
            <div className="history-layout">
              <nav aria-label="保存的版本">
                {history.map((entry) => (
                  <button
                    key={entry.id}
                    className={entry.id === historyEntry.id ? "selected" : ""}
                    onClick={() => setHistoryID(entry.id)}
                  >
                    <strong>
                      {new Date(entry.date).toLocaleString("zh-CN")}
                    </strong>
                    <small>
                      {entry.text.length} 字符 ·{" "}
                      {entry.text.includes("\r\n") ? "CRLF" : "LF"}
                    </small>
                  </button>
                ))}
              </nav>
              <section>
                <header>
                  <span>
                    {new Date(historyEntry.date).toLocaleString("zh-CN")}
                  </span>
                  <small>{historyEntry.text.length} 字符</small>
                </header>
                <pre>
                  {historyEntry.text.slice(0, 200000)}
                  {historyEntry.text.length > 200000
                    ? "\n\n… 预览已截断，恢复时使用完整版本。"
                    : ""}
                </pre>
              </section>
            </div>
          ) : (
            <p className="empty">首次保存后，版本会出现在这里。</p>
          )}
          <div className="dialog-actions">
            <p className="muted">恢复后可检查并重新保存。</p>
            <Button onClick={() => setDialog(null)}>取消</Button>
            <Button
              className="primary"
              disabled={!historyEntry}
              onClick={() => {
                updateDoc({ text: historyEntry.text });
                setDialog(null);
                toast("已恢复到编辑器，保存后写入文件");
              }}
            >
              恢复到编辑器
            </Button>
          </div>
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
                      memoriesForSaving(
                        current.current.conversations,
                        current.current.config,
                      ),
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
createRoot(document.getElementById("root")).render(<App />);

const {
  app,
  BrowserWindow,
  ipcMain,
  dialog,
  safeStorage,
  shell,
  protocol,
  net,
  Menu,
} = require("electron");
const fs = require("node:fs/promises");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const {
  Store,
  readDocument,
  saveDocument,
  listMarkdown,
  atomicWrite,
} = require("./store.cjs");
const { runTurn, endpoint } = require("./agents.cjs");
protocol.registerSchemesAsPrivileged([
  {
    scheme: "mirror-asset",
    privileges: { standard: true, secure: true, supportFetchAPI: true },
  },
]);
let win,
  store,
  closing = false;
const allowed = new Set();
const jobs = new Map();
const filters = [
  { name: "Markdown", extensions: ["md", "markdown", "mdown", "txt"] },
];
const presets = [
  {
    id: "codex",
    name: "Codex",
    kind: "codex",
    model: "",
    executable: "",
    effort: "",
  },
  {
    id: "claude",
    name: "Claude Code",
    kind: "claude",
    model: "",
    executable: "",
  },
  {
    id: "http",
    name: "兼容 HTTP 服务",
    kind: "http",
    endpoint: "http://127.0.0.1:18789/v1",
    model: "",
    executable: "",
  },
  {
    id: "custom",
    name: "自定义命令",
    kind: "custom",
    executable: "",
    arguments: "[]",
    model: "",
  },
];
function handle(name, fn) {
  ipcMain.handle(name, async (event, ...args) => {
    if (event.sender !== win?.webContents) throw new Error("不受信任的窗口。");
    try {
      return { ok: true, value: await fn(...args) };
    } catch (error) {
      return { ok: false, error: error.message };
    }
  });
}
function permitted(file) {
  if (typeof file !== "string" || !allowed.has(path.resolve(file)))
    throw new Error("请先通过文件选择器打开此文件。");
  return path.resolve(file);
}
async function open(file) {
  const document = await readDocument(file);
  allowed.add(document.path);
  return document;
}
async function settings() {
  return store.read("settings", {
    theme: "light",
    mode: "split",
    fontSize: 16,
    selectedAgent: "codex",
    profiles: presets,
  });
}
async function credential(id) {
  const secrets = await store.read("credentials", {});
  if (!secrets[id]) return "";
  if (!safeStorage.isEncryptionAvailable())
    throw new Error("系统加密服务不可用，无法读取密钥。");
  return safeStorage.decryptString(Buffer.from(secrets[id], "base64"));
}
async function assetPath(url) {
  const parsed = new URL(url);
  const document = permitted(parsed.searchParams.get("doc"));
  const source = parsed.searchParams.get("src");
  if (!source || path.isAbsolute(source) || /^[a-z]+:/i.test(source))
    throw new Error("图片路径无效。");
  const root = await fs.realpath(path.dirname(document));
  const candidate = await fs.realpath(path.resolve(root, source));
  const relative = path.relative(root, candidate);
  if (
    relative.startsWith("..") ||
    path.isAbsolute(relative) ||
    !/\.(png|jpe?g|gif|webp|avif|bmp)$/i.test(candidate)
  )
    throw new Error("仅支持文档目录内的本地图片。");
  const stat = await fs.stat(candidate);
  if (stat.size > 20 * 1024 * 1024) throw new Error("图片过大。");
  return candidate;
}
async function exportedHTML(html, dark) {
  // The renderer already sanitizes Markdown; disable executable markup again at
  // the document level through CSP. Inline every permitted local image/font.
  for (const match of html.matchAll(/src="(mirror-asset:[^"]+)"/g)) {
    try {
      const file = await assetPath(match[1].replace(/&amp;/g, "&"));
      const ext = path.extname(file).slice(1).replace("jpg", "jpeg");
      html = html.replaceAll(
        match[1],
        `data:image/${ext};base64,${(await fs.readFile(file)).toString("base64")}`,
      );
    } catch {
      html = html.replaceAll(match[0], 'alt="图片不可用"');
    }
  }
  const katexRoot = path.join(
    __dirname,
    process.env.MIRROR_DEV_URL ? "../public/katex" : "../dist/katex",
  );
  let css = await fs.readFile(path.join(katexRoot, "katex.min.css"), "utf8");
  for (const match of css.matchAll(/url\(([^)]+)\)/g)) {
    const font = path.resolve(katexRoot, match[1]);
    if (font.startsWith(katexRoot + path.sep))
      css = css.replaceAll(
        match[0],
        `url(data:font/woff2;base64,${(await fs.readFile(font)).toString("base64")})`,
      );
  }
  return `<!doctype html><html lang="zh-CN"><meta charset="UTF-8"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:"><title>Mirror 导出</title><style>${css}\nbody{color:${dark ? "#e9e4df" : "#302e2c"};background:${dark ? "#202120" : "#fff"};margin:0;font:17px/1.9 Georgia,'Noto Serif CJK SC','SimSun',serif}article{max-width:800px;margin:60px auto;padding:0 40px}h1,h2,h3{line-height:1.4}h1{font-size:2.2em}h2{border-bottom:1px solid #aaa4;padding-bottom:.4em}blockquote{border-left:3px solid #b95732;margin:24px 0;padding:10px 24px;background:#8881}pre{white-space:pre-wrap;background:#8881;padding:18px;border-radius:8px;font:13px/1.6 Consolas,monospace}code{font-family:Consolas,monospace}table{border-collapse:collapse;width:100%}td,th{padding:8px 12px;border:1px solid #aaa5}img,svg{max-width:100%}a{color:#b95732}.mermaid{text-align:center}.task-list-item{list-style:none}@media print{body{background:white;color:#222}article{margin:0;max-width:none;padding:0}pre,blockquote,tr,svg{break-inside:avoid}a{color:inherit}}</style><article>${html}</article></html>`;
}
function registerIPC() {
  handle("bootstrap", async () => {
    const session = await store.read("session", { tabs: [] });
    for (const tab of session.tabs || []) {
      if (!tab.path) continue;
      allowed.add(path.resolve(tab.path));
      // Clean tabs track the current disk version; dirty tabs retain their
      // original timestamp so saving can detect changes made while closed.
      if (tab.text === tab.savedText) {
        try {
          const fresh = await readDocument(tab.path);
          Object.assign(tab, fresh, { savedText: fresh.text });
        } catch {
          tab.savedText = null;
        }
      }
    }
    if (session.folder) {
      try {
        session.folder.files = await listMarkdown(session.folder.root);
        session.folder.files.forEach((f) => allowed.add(path.resolve(f.path)));
      } catch {
        session.folder = null;
      }
    }
    const config = await settings();
    return {
      session,
      settings: config,
      recent: await store.read("recent", []),
      conversations: await store.read("conversations", []),
      hasCredentials: Object.keys(await store.read("credentials", {})),
    };
  });
  handle("open", async (file) => {
    if (file) return open(permitted(file));
    const result = await dialog.showOpenDialog(win, {
      filters,
      properties: ["openFile", "multiSelections"],
    });
    if (result.canceled) return [];
    return Promise.all(result.filePaths.map(open));
  });
  handle("recent-open", async (file) => {
    const recent = await store.read("recent", []);
    if (!recent.includes(file)) throw new Error("文件不在最近列表中。");
    return open(file);
  });
  handle("folder", async () => {
    const result = await dialog.showOpenDialog(win, {
      properties: ["openDirectory"],
    });
    if (result.canceled) return null;
    const root = result.filePaths[0];
    const files = await listMarkdown(root);
    files.forEach((file) => allowed.add(path.resolve(file.path)));
    return { root, name: path.basename(root), files };
  });
  handle("folder-refresh", async (root) => {
    const session = await store.read("session", { tabs: [] });
    if (session.folder?.root !== root) throw new Error("请先打开文件夹。");
    const files = await listMarkdown(root);
    files.forEach((file) => allowed.add(path.resolve(file.path)));
    return files;
  });
  handle("save", async (doc, saveAs) => {
    let file = doc.path && permitted(doc.path);
    if (!file || saveAs) {
      const result = await dialog.showSaveDialog(win, {
        defaultPath: file || doc.name || "未命名.md",
        filters,
      });
      if (result.canceled) return null;
      file = result.filePath;
      allowed.add(path.resolve(file));
    }
    let result = await saveDocument(
      file,
      doc.text,
      !saveAs && doc.path ? doc.stamp : null,
    );
    if (result.conflict) {
      const answer = await dialog.showMessageBox(win, {
        type: "warning",
        message: "文件已在其他程序中更改。",
        detail: "覆盖会替换磁盘上的版本。你也可以取消并另存为新文件。",
        buttons: ["取消", "覆盖磁盘文件"],
        defaultId: 0,
        cancelId: 0,
      });
      if (answer.response !== 1) return null;
      result = await saveDocument(file, doc.text, null, true);
    }
    await store.snapshot({ ...doc, path: file });
    const recent = await store.read("recent", []);
    await store.write(
      "recent",
      [file, ...recent.filter((value) => value !== file)].slice(0, 12),
    );
    return result;
  });
  handle("session-save", (session) => store.write("session", session));
  handle("settings-save", async (config) => {
    if (
      !["light", "dark", "system"].includes(config.theme) ||
      !["edit", "split", "read"].includes(config.mode)
    )
      throw new Error("设置格式无效。");
    if (!Array.isArray(config.profiles) || config.profiles.length > 30)
      throw new Error("智能体配置无效。");
    for (const profile of config.profiles) {
      if (!["codex", "claude", "http", "custom"].includes(profile.kind))
        throw new Error("不支持的智能体类型。");
      if (profile.kind === "http") endpoint(profile.endpoint);
      if (
        profile.effort &&
        !["minimal", "low", "medium", "high", "xhigh"].includes(profile.effort)
      )
        throw new Error("无效的思考深度。");
      delete profile.token;
    }
    await store.write("settings", config);
  });
  handle("credential-save", async (id, token) => {
    if (
      !safeStorage.isEncryptionAvailable() ||
      (process.platform === "linux" &&
        safeStorage.getSelectedStorageBackend() === "basic_text")
    )
      throw new Error("系统安全存储不可用，拒绝明文保存密钥。");
    const secrets = await store.read("credentials", {});
    if (token)
      secrets[id] = safeStorage.encryptString(token).toString("base64");
    else delete secrets[id];
    await store.write("credentials", secrets);
  });
  handle("history", (doc) => store.history(doc));
  handle("conversations-save", (conversations) =>
    store.write("conversations", conversations),
  );
  handle("agent-start", async ({ id, profile, reference, messages }) => {
    if (jobs.has(id)) throw new Error("此对话正在生成回复。");
    if (
      !Array.isArray(messages) ||
      messages.some(
        (m) =>
          !["user", "assistant"].includes(m.role) ||
          typeof m.content !== "string",
      )
    )
      throw new Error("对话格式无效。");
    const config = await settings();
    const configured = config.profiles.find((p) => p.id === profile.id);
    if (
      !configured ||
      !["codex", "claude", "http", "custom"].includes(profile.kind)
    )
      throw new Error("请先配置智能体。");
    const controller = new AbortController();
    jobs.set(id, controller);
    const send = (event) => {
      if (!win.isDestroyed())
        win.webContents.send("agent-event", { id, ...event });
    };
    // Detach the turn from IPC so the UI can issue cancellation immediately.
    Promise.resolve().then(async () => {
      const timer = setTimeout(() => controller.abort(), 5 * 60_000);
      try {
        const token =
          profile.kind === "http" ? await credential(profile.id) : "";
        const content = await runTurn(
          profile,
          token,
          reference,
          messages,
          (delta) => send({ type: "delta", delta }),
          controller.signal,
        );
        send({ type: "done", content });
      } catch (error) {
        send({
          type: "error",
          error: controller.signal.aborted ? "已停止生成。" : error.message,
        });
      } finally {
        clearTimeout(timer);
        jobs.delete(id);
      }
    });
    return true;
  });
  handle("agent-stop", (id) => {
    jobs.get(id)?.abort();
    return true;
  });
  handle("export", async ({ html, format, name, dark }) => {
    if (!["html", "pdf"].includes(format))
      throw new Error("不支持的导出格式。");
    const result = await dialog.showSaveDialog(win, {
      defaultPath: `${name.replace(/\.[^.]+$/, "")}.${format}`,
      filters: [{ name: format.toUpperCase(), extensions: [format] }],
    });
    if (result.canceled) return null;
    const content = await exportedHTML(html, dark);
    if (format === "html") await atomicWrite(result.filePath, content);
    else {
      const printWindow = new BrowserWindow({
        show: false,
        webPreferences: {
          sandbox: true,
          javascript: false,
          contextIsolation: true,
        },
      });
      try {
        await printWindow.loadURL(
          `data:text/html;charset=utf-8,${encodeURIComponent(content)}`,
        );
        await fs.writeFile(
          result.filePath,
          await printWindow.webContents.printToPDF({
            printBackground: true,
            pageSize: "A4",
            margins: { top: 0.6, bottom: 0.6, left: 0.5, right: 0.5 },
          }),
        );
      } finally {
        printWindow.destroy();
      }
    }
    return result.filePath;
  });
  handle("external", async (value) => {
    const url = new URL(value);
    if (["https:", "http:"].includes(url.protocol))
      await shell.openExternal(url.href);
  });
  handle("window", (action) => {
    if (action === "minimize") win.minimize();
    if (action === "maximize")
      win.isMaximized() ? win.unmaximize() : win.maximize();
    if (action === "close") win.close();
  });
  handle("quit-ready", async (session) => {
    await store.write("session", session);
    for (const job of jobs.values()) job.abort();
    closing = true;
    win.close();
  });
}
function createWindow() {
  win = new BrowserWindow({
    width: 1440,
    height: 940,
    minWidth: 880,
    minHeight: 600,
    frame: false,
    backgroundColor: "#f5f4f2",
    title: "Mirror",
    icon: path.join(__dirname, "../dist/icon.png"),
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  Menu.setApplicationMenu(null);
  win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  win.webContents.on("will-navigate", (event) => event.preventDefault());
  win.webContents.session.setPermissionRequestHandler(
    (_wc, _permission, callback) => callback(false),
  );
  win.on("close", (event) => {
    if (!closing) {
      event.preventDefault();
      win.webContents.send("close-request");
    }
  });
  if (process.env.MIRROR_DEV_URL) win.loadURL(process.env.MIRROR_DEV_URL);
  else win.loadFile(path.join(__dirname, "../dist/index.html"));
  win.webContents.on("did-finish-load", async () => {
    for (const file of process.argv
      .slice(1)
      .filter((x) => /\.(md|markdown|mdown|txt)$/i.test(x))) {
      try {
        win.webContents.send("file-opened", await open(file));
      } catch (error) {
        dialog.showErrorBox("无法打开文件", error.message);
      }
    }
  });
}
if (process.env.MIRROR_TEST_DATA)
  app.setPath("userData", process.env.MIRROR_TEST_DATA);
const single = app.requestSingleInstanceLock();
if (!single) app.quit();
else {
  app.on("second-instance", async (_event, args) => {
    for (const file of args.filter((x) =>
      /\.(md|markdown|mdown|txt)$/i.test(x),
    )) {
      try {
        win.webContents.send("file-opened", await open(file));
      } catch (error) {
        dialog.showErrorBox("无法打开文件", error.message);
      }
    }
    if (win.isMinimized()) win.restore();
    win.focus();
  });
  app.whenReady().then(() => {
    store = new Store(app.getPath("userData"));
    protocol.handle("mirror-asset", async (request) => {
      try {
        return await net.fetch(
          pathToFileURL(await assetPath(request.url)).href,
        );
      } catch {
        return new Response("Not found", { status: 404 });
      }
    });
    registerIPC();
    createWindow();
  });
  app.on("window-all-closed", () => app.quit());
}

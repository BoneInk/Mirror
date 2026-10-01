const { contextBridge, ipcRenderer, webUtils } = require("electron");
const channels = [
  "bootstrap",
  "open",
  "recent-open",
  "folder",
  "folder-refresh",
  "workspace-search",
  "link-open",
  "save",
  "session-save",
  "settings-save",
  "credential-save",
  "history",
  "conversations-save",
  "agent-start",
  "agent-models",
  "agent-discover",
  "codex-threads",
  "codex-history",
  "codex-copy",
  "agent-stop",
  "export",
  "external",
  "window",
  "quit-ready",
];
contextBridge.exposeInMainWorld("mirror", {
  call: async (name, ...args) => {
    if (!channels.includes(name)) throw new Error("不支持的操作。");
    const response = await ipcRenderer.invoke(name, ...args);
    if (!response.ok) throw new Error(response.error);
    return response.value;
  },
  on: (name, callback) => {
    if (
      ![
        "agent-event",
        "close-request",
        "file-opened",
        "document-changed",
        "folder-changed",
        "folder-opened",
        "document-error",
      ].includes(name)
    )
      throw new Error("不支持的事件。");
    const listener = (_event, value) => callback(value);
    ipcRenderer.on(name, listener);
    return () => ipcRenderer.removeListener(name, listener);
  },
});
window.addEventListener("dragover", (event) => {
  if (event.dataTransfer?.types.includes("Files")) event.preventDefault();
});
window.addEventListener("drop", (event) => {
  if (!event.dataTransfer?.files.length) return;
  event.preventDefault();
  const files = [...event.dataTransfer.files]
    .map((file) => webUtils.getPathForFile(file))
    .filter(Boolean);
  if (files.length) ipcRenderer.invoke("drop-open", files);
});

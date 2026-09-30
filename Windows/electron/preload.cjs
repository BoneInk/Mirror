const { contextBridge, ipcRenderer } = require("electron");
const channels = [
  "bootstrap",
  "open",
  "recent-open",
  "folder",
  "folder-refresh",
  "save",
  "session-save",
  "settings-save",
  "credential-save",
  "history",
  "conversations-save",
  "agent-start",
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
    if (!["agent-event", "close-request", "file-opened"].includes(name))
      throw new Error("不支持的事件。");
    const listener = (_event, value) => callback(value);
    ipcRenderer.on(name, listener);
    return () => ipcRenderer.removeListener(name, listener);
  },
});

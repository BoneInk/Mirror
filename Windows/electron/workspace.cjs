const fs = require("node:fs");
const fsp = require("node:fs/promises");
const path = require("node:path");
const { readDocument, listMarkdown } = require("./store.cjs");

async function searchWorkspace(root, query) {
  if (typeof query !== "string" || !query.trim() || query.length > 500)
    return [];
  const needle = query.toLocaleLowerCase();
  const results = [];
  for (const file of await listMarkdown(root)) {
    try {
      const document = await readDocument(file.path);
      for (const [line, text] of document.text.split(/\r?\n/).entries()) {
        const column = text.toLocaleLowerCase().indexOf(needle);
        if (column >= 0)
          results.push({
            ...file,
            line,
            column,
            text: text.slice(Math.max(0, column - 80), column + 220),
          });
        if (results.length >= 200) return results;
      }
    } catch {
      /* Removed, unreadable or oversized files do not abort a search. */
    }
  }
  return results;
}

async function resolveDocumentLink(document, href, workspace) {
  if (
    typeof href !== "string" ||
    !href ||
    /^[a-z][a-z\d+.-]*:/i.test(href) ||
    /^[\\/]/.test(href)
  )
    throw Error("只支持相对文档链接。");
  const [file, fragment = ""] = href.split("#");
  const root = await fsp.realpath(workspace || path.dirname(document));
  const target = await fsp.realpath(
    path.resolve(path.dirname(document), decodeURIComponent(file)),
  );
  const relative = path.relative(root, target);
  if (
    relative === ".." ||
    relative.startsWith(".." + path.sep) ||
    path.isAbsolute(relative)
  )
    throw Error("链接超出文档或工作区目录，请通过文件选择器打开。");
  return { file: target, fragment: decodeURIComponent(fragment) };
}

class DocumentWatcher {
  constructor(onChange, onFolderChange) {
    this.watchers = [];
    this.pending = new Map();
    this.onChange = onChange;
    this.onFolderChange = onFolderChange;
  }
  update(files, folder) {
    const signature = JSON.stringify([
      files
        .filter(Boolean)
        .map((file) => path.resolve(file))
        .sort(),
      folder || null,
    ]);
    if (signature === this.signature) return;
    this.close();
    this.signature = signature;
    const targets = new Set(
      files.filter(Boolean).map((file) => path.resolve(file)),
    );
    const notify = (file) => {
      clearTimeout(this.pending.get(file));
      this.pending.set(
        file,
        setTimeout(async () => {
          this.pending.delete(file);
          try {
            this.onChange(await readDocument(file));
          } catch (error) {
            if (error.code === "ENOENT")
              this.onChange({ path: file, missing: true });
          }
        }, 180),
      );
    };
    for (const dir of new Set([...targets].map((file) => path.dirname(file)))) {
      try {
        const watcher = fs.watch(dir, (_event, name) => {
          if (!name) {
            for (const file of targets)
              if (path.dirname(file) === dir) notify(file);
          } else {
            const file = path.join(dir, name.toString());
            for (const target of targets)
              if (target.toLowerCase() === file.toLowerCase()) notify(target);
          }
        });
        watcher.on("error", () => {});
        this.watchers.push(watcher);
      } catch {
        /* Save still detects conflicts when watching is unavailable. */
      }
    }
    if (folder) {
      try {
        const watcher = fs.watch(
          folder,
          { recursive: true },
          (_event, name) => {
            if (
              name &&
              /(^|[\\/])(?:\.|node_modules|dist|build|vendor)/.test(
                name.toString(),
              )
            )
              return;
            clearTimeout(this.folderTimer);
            this.folderTimer = setTimeout(
              () => this.onFolderChange(folder),
              300,
            );
          },
        );
        watcher.on("error", () => {});
        this.watchers.push(watcher);
      } catch {
        /* Platforms without recursive watches retain manual refresh. */
      }
    }
  }
  close() {
    this.signature = null;
    this.watchers.forEach((watcher) => watcher.close());
    this.watchers = [];
    this.pending.forEach(clearTimeout);
    this.pending.clear();
    clearTimeout(this.folderTimer);
  }
}
module.exports = { searchWorkspace, resolveDocumentLink, DocumentWatcher };

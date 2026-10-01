const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const MARKDOWN = /\.(md|markdown|mdown|txt)$/i;
async function atomicWrite(target, content) {
  await fs.mkdir(path.dirname(target), { recursive: true });
  const temporary = `${target}.${crypto.randomUUID()}.tmp`;
  try {
    await fs.writeFile(temporary, content, { encoding: "utf8", flag: "wx" });
    // Windows readers and scanners can briefly hold the destination open.
    // Retry the atomic replacement; never remove the original as a fallback.
    for (let attempt = 0; ; attempt++) {
      try {
        await fs.rename(temporary, target);
        break;
      } catch (error) {
        if (attempt >= 5 || !["EPERM", "EBUSY", "EACCES"].includes(error.code))
          throw error;
        await new Promise((resolve) => setTimeout(resolve, 50 * (attempt + 1)));
      }
    }
  } finally {
    await fs.unlink(temporary).catch(() => {});
  }
}
async function readDocument(file) {
  if (!MARKDOWN.test(file)) throw new Error("只支持 Markdown 和纯文本文件。");
  const info = await fs.stat(file);
  if (!info.isFile() || info.size > 10 * 1024 * 1024)
    throw new Error("文件过大（上限 10 MB）或不是普通文件。");
  return {
    path: path.resolve(file),
    name: path.basename(file),
    text: (await fs.readFile(file, "utf8")).replace(/^\uFEFF/, ""),
    stamp: info.mtimeMs,
  };
}
async function saveDocument(file, text, stamp, force = false) {
  if (!MARKDOWN.test(file)) throw new Error("请选择 .md 或 .txt 文件。");
  if (!force && stamp != null) {
    const current = await fs.stat(file).catch((error) => {
      if (error.code === "ENOENT") return null;
      throw error;
    });
    if (!current || current.mtimeMs !== stamp) return { conflict: true };
  }
  await atomicWrite(file, text);
  return {
    path: file,
    name: path.basename(file),
    stamp: (await fs.stat(file)).mtimeMs,
  };
}
async function listMarkdown(root) {
  const results = [];
  async function walk(dir, depth) {
    if (depth > 6 || results.length >= 2000) return;
    for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
      if (
        entry.name.startsWith(".") ||
        ["node_modules", "dist", "vendor", "build"].includes(entry.name)
      )
        continue;
      const file = path.join(dir, entry.name);
      if (entry.isDirectory()) await walk(file, depth + 1);
      else if (entry.isFile() && MARKDOWN.test(entry.name))
        results.push({
          path: file,
          name: entry.name,
          relative: path.relative(root, file),
        });
      if (results.length >= 2000) break;
    }
  }
  await walk(root, 0);
  return results.sort((a, b) => a.relative.localeCompare(b.relative, "zh-CN"));
}
class Store {
  constructor(root) {
    this.root = root;
    this.queue = Promise.resolve();
  }
  async read(name, fallback) {
    try {
      return JSON.parse(
        await fs.readFile(path.join(this.root, `${name}.json`), "utf8"),
      );
    } catch (error) {
      if (error.code === "ENOENT") return fallback;
      throw error;
    }
  }
  write(name, data) {
    const operation = this.queue
      .catch(() => {})
      .then(() =>
        atomicWrite(
          path.join(this.root, `${name}.json`),
          JSON.stringify(data, null, 2),
        ),
      );
    this.queue = operation;
    return operation;
  }
  async snapshot(document) {
    const key = crypto
      .createHash("sha256")
      .update(document.path || document.id)
      .digest("hex");
    const name = `history/${key}`;
    const entries = await this.read(name, []);
    if (entries[0]?.text === document.text) return;
    entries.unshift({
      id: crypto.randomUUID(),
      date: new Date().toISOString(),
      text: document.text,
    });
    await this.write(name, entries.slice(0, 30));
  }
  history(document) {
    const key = crypto
      .createHash("sha256")
      .update(document.path || document.id)
      .digest("hex");
    return this.read(`history/${key}`, []);
  }
}
module.exports = {
  atomicWrite,
  readDocument,
  saveDocument,
  listMarkdown,
  Store,
};

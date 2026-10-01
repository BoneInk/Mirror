const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const {
  atomicWrite,
  readDocument,
  saveDocument,
  listMarkdown,
  Store,
} = require("../electron/store.cjs");

test("atomic replacement retries transient locks and retains the original on permanent failure", async (t) => {
  const root = await fixture(t),
    file = path.join(root, "locked.md");
  await fs.writeFile(file, "original");
  const rename = fs.rename;
  let attempts = 0;
  t.after(() => {
    fs.rename = rename;
  });
  fs.rename = async (...args) => {
    if (++attempts < 3)
      throw Object.assign(Error("busy fixture"), { code: "EBUSY" });
    return rename(...args);
  };
  await atomicWrite(file, "replacement");
  assert.equal(await fs.readFile(file, "utf8"), "replacement");
  assert.equal(attempts, 3);
  fs.rename = async () => {
    throw Object.assign(Error("denied fixture"), { code: "EACCES" });
  };
  await assert.rejects(atomicWrite(file, "must not replace"), /denied/);
  assert.equal(await fs.readFile(file, "utf8"), "replacement");
  assert.deepEqual(await fs.readdir(root), ["locked.md"]);
  fs.rename = rename;
});
async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "mirror-test-"));
  t.after(() => fs.rm(root, { recursive: true }));
  return root;
}
test("Unicode documents, external conflicts, deleted-file conflicts and explicit overwrite", async (t) => {
  const root = await fixture(t);
  const file = path.join(root, "文章.md");
  await fs.writeFile(file, "\uFEFF# 中文\r\n文字 🪞");
  const opened = await readDocument(file);
  assert.equal(opened.text, "# 中文\r\n文字 🪞");
  await fs.writeFile(file, "其他程序更改");
  await fs.utimes(file, new Date(), new Date(Date.now() + 5000));
  assert.deepEqual(await saveDocument(file, "不能覆盖", opened.stamp), {
    conflict: true,
  });
  assert.equal(await fs.readFile(file, "utf8"), "其他程序更改");
  const result = await saveDocument(file, "确认覆盖", opened.stamp, true);
  assert.ok(result.stamp);
  await fs.unlink(file);
  assert.deepEqual(await saveDocument(file, "不能自动重建", result.stamp), {
    conflict: true,
  });
  assert.equal(
    (await fs.readdir(root)).filter((x) => x.endsWith(".tmp")).length,
    0,
  );
});
test("folder listing is bounded, ignores dependency directories and symlinks", async (t) => {
  const root = await fixture(t);
  await fs.mkdir(path.join(root, "子目录"));
  await fs.mkdir(path.join(root, "node_modules"));
  await fs.writeFile(path.join(root, "子目录", "正文.md"), "# 正文");
  await fs.writeFile(path.join(root, "node_modules", "忽略.md"), "");
  await fs.writeFile(path.join(root, "图片.png"), "");
  await fs.symlink(path.join(root, "子目录"), path.join(root, "link"), "dir");
  const list = await listMarkdown(root);
  assert.equal(list.length, 1);
  assert.equal(list[0].name, "正文.md");
});
test("draft writes are serialized and history is deduplicated and capped at 30 versions", async (t) => {
  const store = new Store(await fixture(t));
  await Promise.all(
    Array.from({ length: 15 }, (_, n) =>
      store.write("session", { text: `草稿 ${n}` }),
    ),
  );
  assert.deepEqual(await store.read("session"), { text: "草稿 14" });
  for (let n = 0; n < 35; n++)
    await store.snapshot({ id: "document-1", text: `版本 ${n}` });
  await store.snapshot({ id: "document-1", text: "版本 34" });
  const history = await store.history({ id: "document-1" });
  assert.equal(history.length, 30);
  assert.equal(history[0].text, "版本 34");
  assert.deepEqual(await store.history({ id: "document-2" }), []);
});

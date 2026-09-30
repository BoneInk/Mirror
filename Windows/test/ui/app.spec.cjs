const { test, expect, _electron: electron } = require("@playwright/test");
const path = require("node:path");
const fs = require("node:fs/promises");
const os = require("node:os");
let application, page, root;
async function launch() {
  application = await electron.launch({
    args: [path.resolve("."), "--no-sandbox"],
    env: { ...process.env, MIRROR_TEST_DATA: root },
  });
  page = await application.firstWindow();
  await expect(page.getByLabel("Markdown 编辑器")).toBeVisible();
}
test.beforeEach(async () => {
  root = await fs.mkdtemp(path.join(os.tmpdir(), "mirror-ui-"));
  await launch();
});
async function stop() {
  if (application) {
    await application.evaluate(({ app }) => app.exit());
    await application.close();
    application = null;
  }
}
test.afterEach(async () => {
  await stop();
  await fs.rm(root, { recursive: true });
});
test("offline Markdown, math, Mermaid, sanitized HTML and persisted view/theme/drafts", async () => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await expect(page.locator(".preview-pane h1")).toHaveText(
    "让想法，在纸上展开",
  );
  await expect(page.locator(".preview-pane .mermaid svg")).toBeVisible();
  await expect(page.locator(".preview-pane .katex")).toBeVisible();
  await page.screenshot({ path: "test-results/windows-light.png" });
  await page
    .getByLabel("Markdown 编辑器")
    .fill(
      '# 新文章\n\n<script>window.pwned=true</script>\n\n<img src="x" onerror="window.pwned=true">\n\n**正文** $E=mc^2$',
    );
  await expect(page.locator(".preview-pane h1")).toHaveText("新文章");
  expect(await page.evaluate(() => window.pwned)).toBeUndefined();
  await page.getByRole("button", { name: "设置", exact: true }).click();
  await page.getByRole("button", { name: "Mirror Dark", exact: true }).click();
  await page.getByLabel("关闭", { exact: true }).click();
  await expect(page.locator(".app")).toHaveClass(/dark/);
  await page.getByRole("button", { name: "阅读", exact: true }).click();
  await expect(page.locator(".editor-pane")).toHaveCount(0);
  await page.screenshot({ path: "test-results/windows-reader-dark.png" });
  await page.waitForTimeout(700);
  await stop();
  application = await electron.launch({
    args: [path.resolve("."), "--no-sandbox"],
    env: { ...process.env, MIRROR_TEST_DATA: root },
  });
  page = await application.firstWindow();
  await expect(page.locator(".app")).toHaveClass(/dark/);
  await expect(page.locator(".workspace")).toHaveClass(/mode-read/);
  await expect(page.locator(".preview-pane h1")).toHaveText("新文章");
  expect(errors).toEqual([]);
});
test("file save, conflict protection, snapshots, HTML/PDF export and recovery", async () => {
  const file = path.join(root, "文章.md");
  await application.evaluate(({ dialog }, file) => {
    dialog.showSaveDialog = async () => ({ canceled: false, filePath: file });
  }, file);
  await page
    .getByLabel("Markdown 编辑器")
    .fill(
      "# 原稿\n\n内容 $E=mc^2$\n\n```mermaid\nflowchart LR\n A[开始] --> B[完成]\n```",
    );
  await page.getByLabel("保存", { exact: true }).click();
  await expect.poll(() => fs.readFile(file, "utf8")).toContain("# 原稿");
  await page.getByLabel("Markdown 编辑器").fill("# 新稿");
  await fs.writeFile(file, "# 外部版本");
  await fs.utimes(file, new Date(), new Date(Date.now() + 5000));
  await application.evaluate(({ dialog }) => {
    dialog.showMessageBox = async () => ({ response: 0 });
  });
  await page.getByLabel("保存", { exact: true }).click();
  await page.waitForTimeout(200);
  expect(await fs.readFile(file, "utf8")).toBe("# 外部版本");
  await application.evaluate(({ dialog }) => {
    dialog.showMessageBox = async () => ({ response: 1 });
  });
  await page.getByLabel("保存", { exact: true }).click();
  await expect.poll(() => fs.readFile(file, "utf8")).toBe("# 新稿");
  await page.getByRole("button", { name: "版本历史" }).click();
  await expect(page.getByRole("button", { name: "恢复到编辑器" })).toHaveCount(
    2,
  );
  await page.getByRole("button", { name: "恢复到编辑器" }).last().click();
  await expect(page.getByLabel("Markdown 编辑器")).toHaveValue(/# 原稿/);
  const htmlFile = path.join(root, "导出.html");
  await application.evaluate(({ dialog }, file) => {
    dialog.showSaveDialog = async () => ({ canceled: false, filePath: file });
  }, htmlFile);
  await page.getByLabel("导出", { exact: true }).click();
  await page.getByRole("button", { name: "HTML · 独立网页" }).click();
  await expect
    .poll(() =>
      fs
        .readFile(htmlFile, "utf8")
        .then((value) => value.includes("<svg"))
        .catch(() => false),
    )
    .toBe(true);
  const exported = await fs.readFile(htmlFile, "utf8");
  expect(exported).toContain("data:font/woff2;base64");
  expect(exported).toContain("katex");
  expect(exported).not.toContain("data-source=");
  const pdfFile = path.join(root, "导出.pdf");
  await application.evaluate(({ dialog }, file) => {
    dialog.showSaveDialog = async () => ({ canceled: false, filePath: file });
  }, pdfFile);
  await page.getByLabel("导出", { exact: true }).click();
  await page.getByRole("button", { name: "PDF · A4 文档" }).click();
  await expect
    .poll(() =>
      fs
        .readFile(pdfFile)
        .then((data) => data.subarray(0, 4).toString())
        .catch(() => ""),
    )
    .toBe("%PDF");
});
test("selection conversation uses custom CLI, streams and retains history without credentials", async () => {
  const cli = path.join(root, "fake.cjs");
  await fs.writeFile(
    cli,
    "let s='';process.stdin.on('data',d=>s+=d);process.stdin.on('end',()=>{const p=JSON.parse(s);process.stdout.write('收到引用：'+p.reference.text+'\\n');setTimeout(()=>process.stdout.write('回答：'+p.messages.at(-1).content),60)})",
  );
  await page.evaluate(
    async ({ executable, cli }) => {
      const data = await window.mirror.call("bootstrap");
      data.settings.selectedAgent = "custom";
      const p = data.settings.profiles.find((p) => p.id === "custom");
      p.executable = executable;
      p.arguments = JSON.stringify([cli]);
      await window.mirror.call("settings-save", data.settings);
    },
    { executable: process.execPath, cli },
  );
  await page.waitForTimeout(700);
  await stop();
  await launch();
  await page.getByLabel("Markdown 编辑器").fill("这是一段引用资料。");
  await page.getByLabel("Markdown 编辑器").evaluate((area) => {
    area.focus();
    area.setSelectionRange(0, 5);
    area.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  });
  await page.getByRole("button", { name: "提问", exact: true }).click();
  await page.getByLabel("提问内容").fill("解释这段内容");
  await page.getByLabel("发送提问").click();
  await expect(page.locator(".message.assistant")).toContainText(
    "回答：解释这段内容",
  );
  await page.screenshot({ path: "test-results/windows-chat.png" });
  await page.waitForTimeout(700);
  const memories = JSON.parse(
    await fs.readFile(path.join(root, "conversations.json"), "utf8"),
  );
  expect(memories[0].reference.text).toBe("这是一段引");
  expect(memories[0].messages).toHaveLength(2);
  expect(JSON.stringify(memories)).not.toContain("token");
  await page.getByLabel("收起对话").click();
  await page.getByRole("button", { name: "对话", exact: true }).click();
  await page.locator(".conversation-list button").first().click();
  await expect(page.locator(".message.assistant")).toContainText(
    "回答：解释这段内容",
  );
});

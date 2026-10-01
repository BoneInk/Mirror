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
  await expect(page.locator(".preview-pane .mermaid svg")).toContainText(
    "收集灵感",
  );
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
  await expect(page.locator(".status-path")).toHaveText(file);
  await expect(page.locator(".status")).toContainText("已保存");
  await page.getByLabel("Markdown 编辑器").fill("# 新稿");
  await expect(page.locator(".status")).toContainText("尚未保存到文件");
  await fs.writeFile(file, "# 外部版本");
  await fs.utimes(file, new Date(), new Date(Date.now() + 5000));
  await application.evaluate(({ dialog }) => {
    dialog.showMessageBox = async () => ({ response: 0 });
  });
  await page.getByLabel("保存", { exact: true }).click();
  await page.waitForTimeout(200);
  expect(await fs.readFile(file, "utf8")).toBe("# 外部版本");
  await expect(page.getByLabel("Markdown 编辑器")).toHaveValue("# 新稿");
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

test("Mermaid zoom, pan, frame resize and reset never modify Markdown or exports", async () => {
  const text = "# 图表\n\n```mermaid\nflowchart LR\n A[开始] --> B[完成]\n```";
  await page.getByLabel("Markdown 编辑器").fill(text);
  await expect(page.locator(".diagram-interactive")).toBeVisible();
  const transform = await page
    .locator(".diagram-content")
    .getAttribute("style");
  await page.getByLabel("放大流程图", { exact: true }).click();
  expect(await page.locator(".diagram-content").getAttribute("style")).not.toBe(
    transform,
  );
  const handle = page.locator(".diagram-resize-bottom");
  const rect = await handle.boundingBox();
  const before = await page
    .locator(".diagram-canvas")
    .evaluate((n) => n.clientHeight);
  await page.mouse.move(rect.x + rect.width / 2, rect.y + rect.height / 2);
  await page.mouse.down();
  await page.mouse.move(rect.x + rect.width / 2, rect.y + 75);
  await page.mouse.up();
  expect(
    await page.locator(".diagram-canvas").evaluate((n) => n.clientHeight),
  ).toBeGreaterThan(before + 20);
  await page.getByLabel("复位并适配流程图", { exact: true }).click();
  await expect(page.getByLabel("Markdown 编辑器")).toHaveValue(text);
  const file = path.join(root, "graph.html");
  await application.evaluate(({ dialog }, file) => {
    dialog.showSaveDialog = async () => ({ canceled: false, filePath: file });
  }, file);
  await page.getByLabel("导出", { exact: true }).click();
  await page.getByRole("button", { name: "HTML · 独立网页" }).click();
  await expect
    .poll(() => fs.readFile(file, "utf8").catch(() => ""))
    .toContain("<svg");
  const html = await fs.readFile(file, "utf8");
  expect(html).not.toContain("diagram-tools");
  expect(html).not.toContain("diagram-resize");
  expect(html).not.toContain("diagram-content");
  await page.screenshot({ path: "test-results/windows-diagram.png" });
});

test("workspace search, relative document links and external conflict banner preserve unsaved edits", async () => {
  const file = path.join(root, "正文.md"),
    related = path.join(root, "相关.md");
  await fs.writeFile(file, "# 正文\n\n[相关](相关.md#目标)\n");
  await fs.writeFile(related, "# 相关\n\n## 目标\n\n查找独特词");
  await application.evaluate(({ dialog }, root) => {
    dialog.showOpenDialog = async () => ({
      canceled: false,
      filePaths: [root],
    });
  }, root);
  await page.getByLabel("打开文件夹", { exact: true }).click();
  await page
    .locator(".file-list button")
    .filter({ hasText: "正文.md" })
    .click();
  await expect(page.getByLabel("Markdown 编辑器")).toHaveValue(/# 正文/);
  await page.waitForTimeout(650);
  await fs.writeFile(file, "# 外部更新\n\n[相关](相关.md#目标)");
  await expect(page.getByLabel("Markdown 编辑器")).toHaveValue(/# 外部更新/);
  await page.getByLabel("Markdown 编辑器").fill("# 本机草稿");
  await fs.writeFile(file, "# 外部冲突");
  await expect(page.getByRole("alert")).toContainText("其他程序中修改");
  await expect(page.getByLabel("Markdown 编辑器")).toHaveValue("# 本机草稿");
  await page.getByRole("button", { name: "重新载入磁盘版本" }).click();
  await expect(page.getByLabel("Markdown 编辑器")).toHaveValue("# 外部冲突");
  await page
    .getByLabel("Markdown 编辑器")
    .fill("# 正文\n\n[相关](相关.md#目标)");
  await page.locator(".preview-pane a").filter({ hasText: "相关" }).click();
  await expect(page.getByLabel("Markdown 编辑器")).toHaveValue(/查找独特词/);
  await page.getByRole("button", { name: "查找", exact: true }).click();
  await page.getByRole("button", { name: "整个工作区", exact: true }).click();
  await page.getByPlaceholder("查找文字…").fill("独特词");
  await expect(page.locator(".search-results")).toContainText("相关.md");
  await page.screenshot({ path: "test-results/windows-workspace.png" });
});

test("Mac themes, typography, editor options and legacy settings migration persist", async () => {
  await page.getByRole("button", { name: "设置", exact: true }).click();
  await page.getByRole("button", { name: "Sepia", exact: true }).click();
  await page.getByLabel("滚动同步", { exact: true }).selectOption("center");
  await page.getByRole("button", { name: "阅读排版", exact: true }).click();
  await page
    .getByLabel("阅读字体", { exact: true })
    .selectOption("'KaiTi', Georgia, serif");
  await page.getByLabel("关闭", { exact: true }).click();
  await page.getByRole("button", { name: "阅读", exact: true }).click();
  await expect(page.getByLabel("阅读工具")).toBeVisible();
  await page.screenshot({ path: "test-results/windows-reader-sepia.png" });
  await page.waitForTimeout(650);
  await stop();
  const settings = JSON.parse(
    await fs.readFile(path.join(root, "settings.json"), "utf8"),
  );
  expect(settings.theme).toBe("sepia");
  expect(settings.scrollSync).toBe("center");
  expect(settings.profiles.some((p) => p.id === "smartwork")).toBe(true);
  application = await electron.launch({
    args: [path.resolve("."), "--no-sandbox"],
    env: { ...process.env, MIRROR_TEST_DATA: root },
  });
  page = await application.firstWindow();
  await expect(page.locator(".preview-pane .prose")).toHaveCSS(
    "font-family",
    /KaiTi/,
  );
});

test("Smartwork profile sends through IPC and shows model discovery without changing old conversations", async () => {
  const http = require("node:http");
  let received;
  const server = http.createServer(async (req, res) => {
    if (req.url === "/api/agent/models") {
      res.setHeader("Content-Type", "application/json");
      return res.end(
        JSON.stringify({
          models: [{ id: "fixture::model", label: "Fixture model" }],
        }),
      );
    }
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    received = JSON.parse(Buffer.concat(chunks));
    res.setHeader("Content-Type", "text/event-stream");
    res.end(
      'data: {"type":"text","content":"Smartwork回复"}\n\ndata: {"type":"result","status":"completed","output":"Smartwork回复"}\n\n',
    );
  });
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  try {
    await page.evaluate(async (base) => {
      const data = await window.mirror.call("bootstrap");
      const p = data.settings.profiles.find((p) => p.id === "smartwork");
      p.endpoint = base;
      p.model = "fixture::model";
      data.settings.selectedAgent = p.id;
      await window.mirror.call("settings-save", data.settings);
    }, `http://127.0.0.1:${server.address().port}`);
    await stop();
    await launch();
    await page.getByLabel("Markdown 编辑器").fill("协议验收引用。");
    await page.getByLabel("Markdown 编辑器").evaluate((area) => {
      area.focus();
      area.setSelectionRange(0, 6);
      area.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
    });
    await page.getByRole("button", { name: "提问", exact: true }).click();
    await page.getByLabel("提问内容").fill("协议问题");
    await page.getByLabel("发送提问").click();
    await expect(page.locator(".message.assistant")).toContainText(
      "Smartwork回复",
    );
    expect(received.prompt).toContain("协议问题");
    await page.getByTitle("切换智能体与模型").click();
    await page.getByRole("button", { name: "模型列表", exact: true }).click();
    await expect(page.locator("#chat-model-options option")).toHaveAttribute(
      "value",
      "fixture::model",
    );
  } finally {
    server.closeAllConnections();
    await new Promise((r) => server.close(r));
  }
});

test("metadata, callouts, footnotes and source anchors render offline and remain sanitized", async () => {
  await page
    .getByLabel("Markdown 编辑器")
    .fill(
      "---\ntitle: 标题\n---\n\n# 标题\n\n> [!NOTE]\n> 资料提示\n\n正文[^1]\n\n[^1]: 脚注 **说明**\n",
    );
  await expect(page.locator(".frontmatter summary")).toHaveText("文档元数据");
  await expect(page.locator(".markdown-alert")).toContainText("资料提示");
  await expect(page.locator(".footnotes")).toContainText("脚注 说明");
  await expect(page.locator(".prose h1")).toHaveAttribute(
    "data-source-line",
    "4",
  );
  await page.locator(".prose sup a").click();
  await expect(page.locator(".footnotes li")).toBeVisible();
});

test("Codex thread picker reads original history through IPC and preserves the reference", async () => {
  const cli = path.join(root, "codex.cjs");
  await fs.writeFile(
    cli,
    `require('readline').createInterface({input:process.stdin}).on('line',line=>{const q=JSON.parse(line);if(q.id==null)return;let result={};if(q.method==='thread/list')result={data:[{id:'original-thread',name:'验收原会话',cwd:'C:\\fixture'}]};if(q.method==='thread/read')result={thread:{turns:[{items:[{type:'userMessage',content:[{text:'原问题'}]},{type:'agentMessage',text:'原回复'}]}]}};console.log(JSON.stringify({id:q.id,result}))})`,
  );
  await page.evaluate(async (executable) => {
    const data = await window.mirror.call("bootstrap");
    data.settings.profiles.find((p) => p.id === "codex").executable =
      executable;
    await window.mirror.call("settings-save", data.settings);
  }, cli);
  await stop();
  await launch();
  await page.getByLabel("Markdown 编辑器").fill("原会话文档引用");
  await page.getByLabel("Markdown 编辑器").evaluate((area) => {
    area.focus();
    area.setSelectionRange(0, 6);
    area.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  });
  await page
    .getByRole("button", { name: "引用到 Codex 会话…", exact: true })
    .click();
  await page.getByText("验收原会话", { exact: true }).click();
  await expect(page.locator(".thread-history")).toContainText("原回复");
  await page
    .getByRole("button", { name: "在 Mirror 继续原会话", exact: true })
    .click();
  await expect(page.locator(".message.assistant")).toContainText("原回复");
  await expect(page.locator(".chat-panel .reference")).toContainText(
    "原会话文档引",
  );
  await expect(
    page.getByRole("button", { name: "刷新原会话历史" }),
  ).toBeVisible();
});

test("Windows safeStorage encrypts credentials and never exposes tokens through bootstrap", async () => {
  const secret = "mirror-fixture-token-only";
  await page.evaluate(async (token) => {
    await window.mirror.call("credential-save", "http", token);
  }, secret);
  const stored = await fs.readFile(path.join(root, "credentials.json"), "utf8");
  expect(stored).not.toContain(secret);
  const bootstrap = await page.evaluate(() => window.mirror.call("bootstrap"));
  expect(bootstrap.hasCredentials).toContain("http");
  expect(JSON.stringify(bootstrap)).not.toContain(secret);
  await page.evaluate(() => window.mirror.call("credential-save", "http", ""));
  expect(
    JSON.parse(await fs.readFile(path.join(root, "credentials.json"), "utf8")),
  ).toEqual({});
});

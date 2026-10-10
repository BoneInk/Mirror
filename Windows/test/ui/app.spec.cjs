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
test("update preferences persist and staged updates offer a restart action", async () => {
  await page.getByRole("button", { name: "设置", exact: true }).click();
  await page.getByRole("tab", { name: "关于 Mirror", exact: true }).click();
  const automatic = page.getByLabel("自动下载并安装更新");
  await expect(automatic).toBeChecked();
  await automatic.uncheck();
  await expect.poll(async () => JSON.parse(await fs.readFile(path.join(root, "settings.json"), "utf8")).automaticallyUpdates).toBe(false);
  await stop(); await launch();
  await page.getByRole("button", { name: "设置", exact: true }).click();
  await page.getByRole("tab", { name: "关于 Mirror", exact: true }).click();
  await expect(page.getByLabel("自动下载并安装更新")).not.toBeChecked();
  await expect(page.getByRole("button", { name: "检查更新", exact: true })).toBeEnabled();
  await application.evaluate(({ BrowserWindow }) => {
    BrowserWindow.getAllWindows()[0].webContents.send("update-state", { ready: true, availableVersion: "v2.0.0", status: "更新已就绪，退出后自动安装。" });
  });
  await expect(page.getByRole("button", { name: "立即重启更新", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "检查更新", exact: true })).toBeDisabled();
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
  await page.getByRole("tab", { name: "主题", exact: true }).click();
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
  await page.keyboard.press("Control+s");
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
  await page.keyboard.press("Control+s");
  await page.waitForTimeout(200);
  expect(await fs.readFile(file, "utf8")).toBe("# 外部版本");
  await expect(page.getByLabel("Markdown 编辑器")).toHaveValue("# 新稿");
  await application.evaluate(({ dialog }) => {
    dialog.showMessageBox = async () => ({ response: 1 });
  });
  await page.keyboard.press("Control+s");

  await expect.poll(() => fs.readFile(file, "utf8")).toBe("# 新稿");
  await page.getByRole("button", { name: "版本历史" }).click();
  await expect(page.locator(".history-layout nav button")).toHaveCount(2);
  await page.locator(".history-layout nav button").last().click();
  await page.getByRole("button", { name: "恢复到编辑器" }).click();
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
  await page.getByLabel("更多操作", { exact: true }).click();
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
  await page.getByRole("tab", { name: "主题", exact: true }).click();
  await page.getByRole("button", { name: "Sepia", exact: true }).click();
  await page.getByRole("tab", { name: "编辑", exact: true }).click();
  await page.getByLabel("滚动同步", { exact: true }).selectOption("center");
  await page.getByRole("tab", { name: "阅读排版", exact: true }).click();
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
    if (req.url === "/api/agent/health") {
      res.setHeader("Content-Type", "application/json");
      return res.end(
        JSON.stringify({
          ok: true,
          name: "smartwork-agent-runtime",
          protocol: "smartwork-agent-turns-v1",
        }),
      );
    }
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
  await page.getByRole("button", { name: "提问", exact: true }).click();
  await page.getByTitle("切换智能体与模型", { exact: true }).click();
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

test("native layout, editor decorations, reading menus and nested settings stay usable", async () => {
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await expect(page.locator(".topbar")).toHaveCSS("height", "54px");
  await expect(page.locator(".rail")).toHaveCSS("width", "58px");
  await page.getByLabel("Markdown 编辑器").fill("# 标题\n\n第一行\n第二行");
  await page.getByRole("button", { name: "设置", exact: true }).click();
  await expect(
    page.getByRole("tab", { name: "智能体", exact: true }),
  ).toHaveAttribute("aria-selected", "true");
  await page.screenshot({ path: "test-results/windows-settings-agents.png" });
  await page.getByRole("tab", { name: "主题", exact: true }).click();
  await page.screenshot({ path: "test-results/windows-settings-themes.png" });
  await page.getByRole("tab", { name: "编辑", exact: true }).click();
  await page.getByLabel("显示行号", { exact: true }).check();
  await page.getByLabel("高亮当前行", { exact: true }).check();
  await page.getByLabel("在预览与导出中保留单行换行", { exact: true }).check();
  await page.keyboard.press("Escape");
  await expect(page.locator(".modal")).toHaveCount(0);
  await expect(page.locator(".line-numbers")).toContainText("4");
  await expect(page.locator(".current-line")).toBeVisible();
  await expect(page.locator(".preview-pane p br")).toHaveCount(1);
  await page.getByRole("button", { name: "阅读", exact: true }).click();
  await page.getByLabel("切换阅读宽度").click();
  await page.getByRole("menuitemradio", { name: "标准", exact: true }).click();
  await page.getByLabel("阅读主题", { exact: true }).click();
  await page.getByRole("menuitemradio", { name: "Sepia", exact: true }).click();
  await page.getByLabel("专注阅读").click();
  await expect(page.locator(".rail")).toHaveCount(0);
  await expect(page.locator(".status")).toHaveCount(0);
  await expect(page.getByLabel("阅读工具")).toBeVisible();
  await page.keyboard.press("Escape");
  await page.getByRole("button", { name: "设置", exact: true }).click();
  await page.getByLabel("添加智能体", { exact: true }).selectOption("custom");
  await expect(
    page.getByRole("dialog", { name: "配置智能体", exact: true }),
  ).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(
    page.getByRole("dialog", { name: "设置", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByRole("dialog", { name: "配置智能体", exact: true }),
  ).toHaveCount(0);
  await page.keyboard.press("Escape");
  expect(errors).toEqual([]);
  await application.evaluate(({ BrowserWindow }) => {
    BrowserWindow.getAllWindows()[0].setSize(960, 720);
  });
  await expect.poll(() => page.evaluate(() => innerWidth)).toBe(960);
  expect(
    await page
      .locator(".app")
      .evaluate((node) => node.scrollWidth <= node.clientWidth),
  ).toBe(true);
  await page.screenshot({ path: "test-results/windows-narrow.png" });
});

test("missing CLI is hidden in chat, can be configured and reappears after installation", async () => {
  const cli = path.join(root, "later.cjs");
  await page.evaluate(async (cli) => {
    const data = await window.mirror.call("bootstrap");
    data.settings.profiles = [
      {
        id: "custom",
        kind: "custom",
        name: "已安装智能体",
        connection: "command",
        executable: "node",
        arguments: "[]",
      },
      {
        id: "later",
        kind: "custom",
        name: "尚未安装智能体",
        connection: "command",
        executable: cli,
        arguments: "[]",
      },
    ];
    data.settings.selectedAgent = "custom";
    await window.mirror.call("settings-save", data.settings);
  }, cli);
  await stop();
  await launch();
  await page.getByLabel("Markdown 编辑器").fill("智能体引用资料");
  await page.getByLabel("Markdown 编辑器").evaluate((area) => {
    area.setSelectionRange(0, 4);
    area.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  });
  await page.getByRole("button", { name: "提问", exact: true }).click();
  await page.getByTitle("切换智能体与模型").click();
  await expect(
    page.locator(".chat-options select").first().locator("option"),
  ).toHaveCount(1);
  await expect(page.locator(".chat-options select").first()).not.toContainText(
    "尚未安装智能体",
  );
  await page.getByLabel("智能体设置", { exact: true }).click();
  await page.locator(".missing-agents summary").click();
  await expect(page.locator(".missing-agents")).toContainText("尚未安装智能体");
  await page
    .locator(".missing-agents")
    .getByRole("button", { name: "配置…" })
    .click();
  await expect(page.getByLabel("可执行文件")).toHaveValue(cli);
  await page.keyboard.press("Escape");
  await fs.writeFile(cli, "process.exit(0)");
  await page.getByRole("button", { name: "检测本机", exact: true }).click();
  await expect(page.locator(".settings-content > .agent-list")).toContainText(
    "尚未安装智能体",
  );
  await page.keyboard.press("Escape");
  await expect(
    page.locator(".chat-options select").first().locator("option"),
  ).toHaveCount(2);
  await page.screenshot({ path: "test-results/windows-chat-options.png" });
});

test("bubble memory can be disabled without deleting old records and can be searched and cleared", async () => {
  await page.evaluate(async () => {
    const data = await window.mirror.call("bootstrap");
    data.settings.profiles = [
      {
        id: "custom",
        kind: "custom",
        name: "本地测试智能体",
        connection: "command",
        executable: "node",
        arguments: "[]",
      },
    ];
    data.settings.selectedAgent = "custom";
    await window.mirror.call("settings-save", data.settings);
    await window.mirror.call("conversations-save", [
      {
        id: "remembered",
        docID: "old",
        name: "旧文档.md",
        reference: { text: "旧引用" },
        profile: { id: "codex", name: "Codex", kind: "codex" },
        messages: [{ role: "user", content: "记忆问题" }],
        date: new Date().toISOString(),
      },
    ]);
  });
  await stop();
  await launch();
  await page.getByRole("button", { name: "设置", exact: true }).click();
  await page.getByRole("tab", { name: "气泡记忆", exact: true }).click();
  await page.getByLabel("记住引用位置和对话", { exact: true }).uncheck();
  await expect(page.locator(".memory-list")).toContainText("记忆问题");
  await page.keyboard.press("Escape");
  await page.getByLabel("Markdown 编辑器").fill("不保存的新引用");
  await page.getByLabel("Markdown 编辑器").evaluate((area) => {
    area.setSelectionRange(0, 4);
    area.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  });
  await page.getByRole("button", { name: "提问", exact: true }).click();
  await expect(page.locator(".chat-panel")).toBeVisible();
  await page.getByLabel("关闭窗口", { exact: true }).click();
  const closed = application.waitForEvent("close");
  await page
    .getByRole("button", { name: "保留草稿并退出", exact: true })
    .click();
  await closed;
  application = null;
  const saved = JSON.parse(
    await fs.readFile(path.join(root, "conversations.json"), "utf8"),
  );
  expect(saved.map((c) => c.id)).toEqual(["remembered"]);
  await launch();
  await page.getByRole("button", { name: "设置", exact: true }).click();
  await page.getByRole("tab", { name: "气泡记忆", exact: true }).click();
  await page.getByLabel("搜索气泡记忆").fill("不存在");
  await expect(page.locator(".memory-list")).toContainText("没有匹配的记录");
  await page.getByLabel("搜索气泡记忆").fill("记忆");
  await page
    .locator(".memory-list")
    .getByRole("button", { name: "删除", exact: true })
    .click();
  await page.getByRole("button", { name: "删除记录", exact: true }).click();
  await expect(page.locator(".memory-list")).toContainText("没有匹配的记录");
  await expect
    .poll(async () =>
      JSON.parse(
        await fs.readFile(path.join(root, "conversations.json"), "utf8"),
      ),
    )
    .toEqual([]);
});

test("no installed default agent opens configuration while preserving the selection", async () => {
  await page.evaluate(
    async (executable) => {
      const data = await window.mirror.call("bootstrap");
      data.settings.profiles = [
        {
          id: "absent",
          kind: "custom",
          name: "未安装的智能体",
          connection: "command",
          executable,
        },
      ];
      data.settings.selectedAgent = "absent";
      await window.mirror.call("settings-save", data.settings);
    },
    path.join(root, "absent.cjs"),
  );
  await stop();
  await launch();
  await page.getByLabel("Markdown 编辑器").fill("保留引用");
  await page.getByLabel("Markdown 编辑器").evaluate((area) => {
    area.setSelectionRange(0, 4);
    area.dispatchEvent(new MouseEvent("mouseup", { bubbles: true }));
  });
  await page.getByRole("button", { name: "提问", exact: true }).click();
  await expect(
    page.getByRole("dialog", { name: "设置", exact: true }),
  ).toBeVisible();
  await expect(page.locator(".chat-panel")).toHaveCount(0);
  await page.keyboard.press("Escape");
  await expect(page.locator(".selection-action")).toHaveText("提问");
  await expect(page.locator(".selection-action button")).toHaveCount(1);
});

test("editor selection follows its focus end, stays still on mouse movement, and anchors the chat", async () => {
  await page.evaluate(async () => {
    const data = await window.mirror.call("bootstrap");
    data.settings.profiles = [
      {
        id: "fixture",
        kind: "custom",
        name: "测试智能体",
        connection: "http",
        endpoint: "http://127.0.0.1:1",
      },
    ];
    data.settings.selectedAgent = "fixture";
    await window.mirror.call("settings-save", data.settings);
  });
  await stop();
  await launch();
  // Keep this caret-to-chat comparison free of responsive sidebar reflow.
  await application.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].setSize(1600, 1100),
  );
  const area = page.getByLabel("Markdown 编辑器");
  await area.fill(
    Array.from({ length: 80 }, (_, i) => `第 ${i + 1} 行 引用资料`).join("\n"),
  );
  const select = (direction) =>
    area.evaluate((area, direction) => {
      area.focus();
      const lines = area.value.split("\n");
      const start = lines.slice(0, 2).join("\n").length + 1;
      const end = lines.slice(0, 6).join("\n").length + 4;
      area.setSelectionRange(start, end, direction);
      area.scrollTop = 0;
    }, direction);
  const toolbar = page.locator(".selection-action");
  await select("forward");
  await expect(toolbar).toBeVisible();
  const forward = await toolbar.boundingBox();
  const areaBox = await area.boundingBox();
  expect(forward.y).toBeGreaterThan(areaBox.y + 70);
  expect(forward.y).toBeLessThan(areaBox.y + 300);
  await select("backward");
  await expect
    .poll(async () => (await toolbar.boundingBox()).y)
    .toBeLessThan(forward.y - 50);
  const backward = await toolbar.boundingBox();
  await page.mouse.move(30, 30);
  expect(await toolbar.boundingBox()).toEqual(backward);
  await area.press("ArrowRight");
  await expect(toolbar).toHaveCount(0);
  await area.evaluate((area) => {
    area.setSelectionRange(0, 0);
    area.scrollTop = 0;
  });
  await area.press("Shift+ArrowRight");
  await expect(toolbar).toBeVisible();
  await select("forward");
  await expect
    .poll(async () => (await toolbar.boundingBox()).y)
    .toBeCloseTo(forward.y, 0);
  const beforeChat = await toolbar.boundingBox();
  await page.getByRole("button", { name: "提问", exact: true }).click();
  const chat = page.locator(".chat-panel");
  await expect(chat).toBeVisible();
  await expect(chat.locator(".reference")).toContainText("第 3 行 引用资料");
  const chatBox = await chat.boundingBox();
  expect(Math.abs(chatBox.x - beforeChat.x)).toBeLessThan(2);
  expect(Math.abs(chatBox.y - beforeChat.y)).toBeLessThan(2);
  const viewport = await page.locator(".workspace").boundingBox();
  expect(chatBox.x + chatBox.width).toBeLessThanOrEqual(
    viewport.x + viewport.width - 7,
  );
  expect(chatBox.y + chatBox.height).toBeLessThanOrEqual(
    viewport.y + viewport.height - 7,
  );
  await page.screenshot({ path: "test-results/windows-selection-chat.png" });
  await page.getByLabel("收起对话").click();
  await select("forward");
  await expect(toolbar).toBeVisible();
  await area.evaluate((area) => {
    area.scrollTop = 500;
  });
  await expect(toolbar).toBeHidden();
  await area.evaluate((area) => {
    area.scrollTop = 0;
  });
  await expect(toolbar).toBeVisible();
  await expect
    .poll(async () => (await toolbar.boundingBox()).y)
    .toBeCloseTo(forward.y, 0);
  await area.fill("\t" + "中文长段落引用内容".repeat(40));
  const layout = await area.evaluate((area) => {
    area.scrollTop = 0;
    const css = getComputedStyle(area),
      rect = area.getBoundingClientRect();
    return {
      left: rect.left + parseFloat(css.paddingLeft),
      top: rect.top + parseFloat(css.paddingTop),
      lineHeight: parseFloat(css.lineHeight),
      fontSize: parseFloat(css.fontSize),
    };
  });
  const end = { x: layout.left + 100, y: layout.top + layout.lineHeight * 3.5 };
  await page.mouse.move(layout.left + 65, layout.top + layout.lineHeight / 2);
  await page.mouse.down();
  await page.mouse.move(end.x, end.y, { steps: 8 });
  await page.mouse.up();
  await expect(toolbar).toBeVisible();
  const wrapped = await toolbar.boundingBox();
  expect(Math.abs(wrapped.y - end.y)).toBeLessThan(layout.lineHeight + 8);
  expect(Math.abs(wrapped.x + 12 - end.x)).toBeLessThan(layout.fontSize + 2);
  await page.screenshot({ path: "test-results/windows-selection-wrapped.png" });
});

test("preview selection tracks forward and backward DOM ranges, flips near the bottom, and survives resize", async () => {
  await page
    .getByLabel("Markdown 编辑器")
    .fill(
      Array.from(
        { length: 40 },
        (_, i) => `段落 ${i + 1}，这是**重点**引用文字。`,
      ).join("\n\n"),
    );
  const paragraphs = page.locator(".preview-pane article p");
  await expect(paragraphs).toHaveCount(40);
  await page.locator(".preview-scroll").evaluate((viewport) => {
    viewport.scrollTop = 0;
  });
  const select = (index, backwards = false) =>
    page.evaluate(
      ({ index, backwards }) => {
        document.activeElement.blur();
        const p = document.querySelectorAll(".preview-pane article p")[index];
        const first = p.firstChild;
        const last = p.lastChild;
        window
          .getSelection()
          .setBaseAndExtent(
            backwards ? last : first,
            backwards ? last.length : 0,
            backwards ? first : last,
            backwards ? 0 : last.length,
          );
      },
      { index, backwards },
    );
  const toolbar = page.locator(".selection-action");
  await select(1);
  await expect(toolbar).toBeVisible();
  const forward = await toolbar.boundingBox();
  const endpoint = await paragraphs.nth(1).evaluate((p) => {
    const r = document.createRange();
    r.setStart(p.lastChild, p.lastChild.length);
    r.collapse(true);
    const rect = r.getBoundingClientRect();
    return { left: rect.left, bottom: rect.bottom };
  });
  const initialWorkspace = await page.locator(".workspace").boundingBox();
  const expectedLeft = Math.max(
    initialWorkspace.x + 8,
    Math.min(
      endpoint.left - 12,
      initialWorkspace.x + initialWorkspace.width - forward.width - 8,
    ),
  );
  await expect
    .poll(async () => Math.abs((await toolbar.boundingBox()).x - expectedLeft))
    .toBeLessThan(2);
  await expect
    .poll(async () => Math.abs((await toolbar.boundingBox()).y - (endpoint.bottom + 8)))
    .toBeLessThan(2);
  await select(1, true);
  const startpoint = await paragraphs.nth(1).evaluate((p) => {
    const r = document.createRange();
    r.setStart(p.firstChild, 0);
    r.collapse(true);
    return r.getBoundingClientRect().left;
  });
  const expectedBackward = Math.max(
    initialWorkspace.x + 8,
    Math.min(
      startpoint - 12,
      initialWorkspace.x + initialWorkspace.width - forward.width - 8,
    ),
  );
  await expect
    .poll(async () => (await toolbar.boundingBox()).x)
    .toBeCloseTo(expectedBackward, 0);
  expect(expectedBackward).toBeLessThan(expectedLeft);
  await page.screenshot({ path: "test-results/windows-selection-preview.png" });
  const bottomIndex = await page.evaluate(() => {
    const viewport = document
      .querySelector(".preview-scroll")
      .getBoundingClientRect();
    return [
      ...document.querySelectorAll(".preview-pane article p"),
    ].findIndex((p) => p.getBoundingClientRect().top >= viewport.bottom);
  });
  expect(bottomIndex).toBeGreaterThan(1);
  await paragraphs.nth(bottomIndex).evaluate((p) => {
    const viewport = document.querySelector(".preview-scroll");
    const caret = document.createRange();
    caret.setStart(p.lastChild, p.lastChild.length);
    caret.collapse(true);
    // Put the actual focus glyph near the bottom, independent of font metrics.
    viewport.scrollTop += caret.getBoundingClientRect().bottom - (viewport.getBoundingClientRect().bottom - 4);
  });
  await select(bottomIndex);
  await expect(toolbar).toHaveAttribute("data-placement", "top");
  await page.evaluate(() => window.getSelection().removeAllRanges());
  await application.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows()[0].setSize(800, 600),
  );
  await expect
    .poll(() => page.locator(".preview-scroll").evaluate((viewport) => viewport.clientHeight))
    .toBeLessThan(500);
  // Chromium completes selection/scroll anchoring on the resize frame.
  await page.evaluate(() => new Promise((resolve) =>
    requestAnimationFrame(() => requestAnimationFrame(resolve)),
  ));
  await page.locator(".preview-scroll").evaluate((viewport) => {
    viewport.scrollTop = 0;
  });
  await select(0);
  await expect(toolbar).toBeVisible();
  const box = await toolbar.boundingBox();
  const workspace = await page.locator(".workspace").boundingBox();
  expect(box.x).toBeGreaterThanOrEqual(workspace.x + 7);
  expect(box.x + box.width).toBeLessThanOrEqual(
    workspace.x + workspace.width - 7,
  );
  await page.locator(".preview-scroll").evaluate((viewport) => {
    viewport.scrollTop = 700;
  });
  await expect(toolbar).toBeHidden();
  await page.locator(".preview-scroll").evaluate((viewport) => {
    viewport.scrollTop = 0;
  });
  await expect(toolbar).toBeVisible();
  await page.evaluate(() => window.getSelection().removeAllRanges());
  await expect(toolbar).toHaveCount(0);
});

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const http = require("node:http");
const {
  searchWorkspace,
  resolveDocumentLink,
  DocumentWatcher,
} = require("../electron/workspace.cjs");
const {
  queryCodex,
  continueThread,
  threadMessages,
  acquireThreadLock,
} = require("../electron/codex.cjs");
const { runTurn } = require("../electron/agents.cjs");
const { listModels } = require("../electron/services.cjs");
async function temporary(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "mirror-parity-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  return root;
}
async function serve(t, handler) {
  const server = http.createServer(handler);
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  t.after(
    () =>
      new Promise((r) => {
        server.closeAllConnections();
        server.close(r);
      }),
  );
  return `http://127.0.0.1:${server.address().port}`;
}
test("workspace search, relative Unicode links, watch rename/save and deleted files", async (t) => {
  const root = await temporary(t),
    file = path.join(root, "正文.md"),
    linked = path.join(root, "相关.md");
  await fs.writeFile(file, "# 标题\n\n搜索引用");
  await fs.writeFile(linked, "# 相关");
  const rows = await searchWorkspace(root, "引用");
  assert.equal(rows.length, 1);
  assert.equal(rows[0].line, 2);
  assert.deepEqual(
    await resolveDocumentLink(file, "%E7%9B%B8%E5%85%B3.md#相关", root),
    { file: await fs.realpath(linked), fragment: "相关" },
  );
  await assert.rejects(resolveDocumentLink(file, "https://example.com", root));
  const outside = path.join(root, "..", path.basename(root) + ".md");
  await fs.writeFile(outside, "private");
  t.after(() => fs.unlink(outside));
  await assert.rejects(
    resolveDocumentLink(file, "../" + path.basename(outside), root),
    /超出/,
  );
  const changes = [];
  const watcher = new DocumentWatcher(
    (value) => changes.push(value),
    () => {},
  );
  t.after(() => watcher.close());
  watcher.update([file], root);
  await fs.writeFile(file, "来自外部编辑器");
  watcher.update([file], root);
  await new Promise((r) => setTimeout(r, 350));
  assert.equal(changes.at(-1).text, "来自外部编辑器");
  await fs.unlink(file);
  await new Promise((r) => setTimeout(r, 350));
  assert.equal(changes.at(-1).missing, true);
});
test("native streaming parsers exclude tools, reconcile finals and reject failed results", async (t) => {
  const root = await temporary(t),
    cli = path.join(root, "agent.cjs");
  await fs.writeFile(
    cli,
    `process.stdin.resume();process.stdin.on('end',()=>{for(const e of [{type:'stream_event',event:{delta:{type:'text_delta',text:'中文'}}},{type:'stream_event',event:{delta:{type:'thinking_delta',text:'private reasoning'}}},{type:'result',result:'中文回答'}]) console.log(JSON.stringify(e))})`,
  );
  for (const kind of ["claude", "codebuddy"]) {
    let stream = "";
    const text = await runTurn(
      { kind, executable: cli },
      "",
      { text: "引用" },
      [{ role: "user", content: "问题" }],
      (d) => (stream += d),
      new AbortController().signal,
    );
    assert.equal(text, "中文回答");
    assert.equal(stream, text);
  }
  await fs.writeFile(
    cli,
    `process.stdin.resume();process.stdin.on('end',()=>console.log(JSON.stringify({type:'result',is_error:true,result:'error diagnostic'})))`,
  );
  await assert.rejects(
    runTurn(
      { kind: "claude", executable: cli },
      "",
      {},
      [],
      () => {},
      new AbortController().signal,
    ),
  );
});
test("Smartwork and WorkBuddy match native protocols; models exclude hidden entries", async (t) => {
  let modelBody,
    workReference = false;
  const base = await serve(t, async (req, res) => {
    const chunks = [];
    for await (const part of req) chunks.push(part);
    res.setHeader("Content-Type", "application/json");
    if (req.url === "/api/agent/models")
      return res.end(
        JSON.stringify({
          models: [
            { id: "provider::model", label: "Model" },
            { id: "hidden", hidden: true },
          ],
        }),
      );
    if (req.url === "/api/agent/turns") {
      modelBody = JSON.parse(Buffer.concat(chunks));
      assert.equal(req.headers["x-auth-token"], "fixture");
      res.setHeader("Content-Type", "text/event-stream");
      return res.end(
        'data: {"type":"text","content":"你好"}\n\ndata: {"type":"result","status":"completed","output":"你好回答"}\n\n',
      );
    }
    assert.equal(req.headers.authorization, "Bearer fixture");
    if (req.url === "/localassistant")
      return res.end(JSON.stringify({ code: 0, data: { online: true } }));
    if (req.method === "POST") {
      workReference = JSON.parse(Buffer.concat(chunks)).content.includes(
        "引用",
      );
      return res.end(
        JSON.stringify({ code: 0, data: { message_id: "message" } }),
      );
    }
    assert.equal(req.url, "/localassistant/message?message_id=message");
    res.end(
      JSON.stringify({
        code: 0,
        data: {
          messages: [
            { role: "assistant", msg_type: "text", content: ["回复", "内容"] },
          ],
        },
      }),
    );
  });
  const smartwork = {
    kind: "smartwork",
    connection: "smartwork",
    endpoint: base,
    model: "provider::model",
  };
  assert.equal((await listModels(smartwork, "fixture")).length, 1);
  assert.equal(
    await runTurn(
      smartwork,
      "fixture",
      { text: "引用" },
      [],
      () => {},
      new AbortController().signal,
    ),
    "你好回答",
  );
  assert.equal(modelBody.modelProvider, "provider");
  assert.equal(modelBody.model, "model");
  assert.equal(
    await runTurn(
      { kind: "workbuddy", connection: "workbuddy", endpoint: base },
      "fixture",
      { text: "引用" },
      [],
      () => {},
      new AbortController().signal,
    ),
    "回复\n内容",
  );
  assert.ok(workReference);
});
test("Codex JSON-RPC initializes, reads history, continues original thread and locks writers", async (t) => {
  const root = await temporary(t),
    cli = path.join(root, "codex.cjs"),
    log = path.join(root, "requests.jsonl");
  await fs.writeFile(
    cli,
    `const fs=require('fs');require('readline').createInterface({input:process.stdin}).on('line',line=>{const q=JSON.parse(line);fs.appendFileSync(${JSON.stringify(log)},line+'\\n');if(q.id==null)return;let result={};if(q.method==='thread/read') result={thread:{turns:[{items:[{type:'userMessage',content:[{text:'旧问题'}]},{type:'agentMessage',text:'旧回复'},{type:'commandExecution',command:'secret'}]}]}};if(q.method==='model/list')result={data:[{model:'fixture-model',supportedReasoningEfforts:[{reasoningEffort:'low'}]}]};if(q.method==='turn/start')result={turn:{id:'turn'}};console.log(JSON.stringify({id:q.id,result}));if(q.method==='turn/start')setTimeout(()=>{console.log(JSON.stringify({method:'item/agentMessage/delta',params:{threadId:q.params.threadId,delta:'原会话回复'}}));console.log(JSON.stringify({method:'turn/completed',params:{threadId:q.params.threadId,turn:{id:'turn',status:'completed'}}}))},15)})`,
  );
  const profile = {
    kind: "codex",
    executable: cli,
    model: "fixture-model",
    effort: "low",
  };
  const result = await queryCodex(profile, "thread/read", {
    threadId: "original",
    includeTurns: true,
  });
  assert.equal(threadMessages(result.thread).length, 2);
  assert.equal((await listModels(profile, "")).at(0).id, "fixture-model");
  const release = await acquireThreadLock(root, "original");
  await assert.rejects(acquireThreadLock(root, "original"), /正在/);
  await release();
  await assert.rejects(
    continueThread({
      profile,
      threadId: "original",
      root,
      guard: async () => true,
    }),
    /退出/,
  );
  assert.equal(
    await continueThread({
      profile,
      threadId: "original",
      root,
      reference: { text: "引用" },
      messages: [{ role: "user", content: "本轮问题" }],
      onDelta: () => {},
      signal: new AbortController().signal,
      guard: async () => false,
    }),
    "原会话回复",
  );
  const requests = (await fs.readFile(log, "utf8"))
    .trim()
    .split("\n")
    .map(JSON.parse);
  const start = requests.find((q) => q.method === "turn/start");
  assert.equal(start.params.threadId, "original");
  assert.equal(start.params.sandboxPolicy.type, "readOnly");
  assert.equal(start.params.approvalPolicy, "never");
  assert.ok(start.params.input[0].text.includes("引用"));
  assert.ok(!start.params.input[0].text.includes("旧问题"));
});

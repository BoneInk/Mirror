const { test } = require("node:test");
const assert = require("node:assert/strict");
const http = require("node:http");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { httpTurn, cliTurn, endpoint } = require("../electron/agents.cjs");
async function server(t, handler) {
  const s = http.createServer(handler);
  await new Promise((r) => s.listen(0, "127.0.0.1", r));
  t.after(
    () =>
      new Promise((r) => {
        s.closeAllConnections();
        s.close(r);
      }),
  );
  return `http://127.0.0.1:${s.address().port}/v1`;
}
test("SSE handles split UTF-8, CRLF, trailing frames and preserves reference/context", async (t) => {
  let request;
  const url = await server(t, async (req, res) => {
    const chunks = [];
    for await (const part of req) chunks.push(part);
    request = JSON.parse(Buffer.concat(chunks));
    assert.equal(req.headers.authorization, "Bearer fake-token");
    res.writeHead(200, { "Content-Type": "text/event-stream" });
    const frame = Buffer.from(
      'data: {"choices":[{"delta":{"content":"中文🪞"}}]}\r\n\r\ndata: {"choices":[{"delta":{"content":"回答"}}]}',
    );
    const split = frame.indexOf(Buffer.from("中文")) + 1;
    res.write(frame.subarray(0, split));
    setTimeout(() => res.end(frame.subarray(split)), 15);
  });
  const deltas = [];
  const reference = { text: "引用内容", path: "C:\\文档\\文章.md", line: 2 };
  const output = await httpTurn(
    { endpoint: url, model: "local-model" },
    "fake-token",
    reference,
    [{ role: "user", content: "问题" }],
    (d) => deltas.push(d),
    new AbortController().signal,
  );
  assert.equal(output, "中文🪞回答");
  assert.equal(deltas.join(""), output);
  assert.ok(request.messages[1].content.includes("引用内容"));
  assert.equal(request.messages.at(-1).content, "问题");
});
test("JSON responses and HTTP errors do not expose server diagnostics", async (t) => {
  const url = await server(t, (_req, res) => {
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify({ choices: [{ message: { content: "答案" } }] }));
  });
  assert.equal(
    await httpTurn(
      { endpoint: url, model: "test" },
      "",
      {},
      [],
      () => {},
      new AbortController().signal,
    ),
    "答案",
  );
  const denied = await server(t, (_req, res) => {
    res.writeHead(401);
    res.end("secret diagnostics");
  });
  await assert.rejects(
    httpTurn(
      { endpoint: denied, model: "test" },
      "",
      {},
      [],
      () => {},
      new AbortController().signal,
    ),
    /HTTP 401/,
  );
});
test("redirects are rejected and active streams can be cancelled", async (t) => {
  const redirect = await server(t, (_req, res) => {
    res.writeHead(302, { Location: "http://127.0.0.1:1" });
    res.end();
  });
  await assert.rejects(
    httpTurn(
      { endpoint: redirect, model: "m" },
      "token",
      {},
      [],
      () => {},
      new AbortController().signal,
    ),
  );
  const controller = new AbortController();
  const url = await server(t, (_req, res) => {
    res.writeHead(200, { "Content-Type": "text/event-stream" });
    res.write('data: {"choices":[{"delta":{"content":"一"}}]}\n\n');
  });
  await assert.rejects(
    httpTurn(
      { endpoint: url, model: "m" },
      "",
      {},
      [],
      () => controller.abort(),
      controller.signal,
    ),
  );
});
test("endpoint rejects credential-bearing URLs and non-HTTP schemes", () => {
  for (const url of [
    "file:///etc/passwd",
    "https://key@example.com/v1",
    "https://example.com/v1?key=secret",
  ])
    assert.throws(() => endpoint(url));
  assert.equal(endpoint("https://example.com/v1/"), "https://example.com/v1");
});
test("custom CLI receives JSON through stdin, never invokes a shell and supports cancellation", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "mirror-agent-"));
  t.after(() => fs.rm(root, { recursive: true }));
  const file = path.join(root, "agent.cjs");
  await fs.writeFile(
    file,
    "let input='';process.stdin.setEncoding('utf8');process.stdin.on('data',d=>input+=d);process.stdin.on('end',()=>{const p=JSON.parse(input);process.stdout.write(p.reference.text+' / '+p.messages.at(-1).content)})",
  );
  const result = await cliTurn(
    {
      kind: "custom",
      executable: process.execPath,
      arguments: JSON.stringify([file]),
    },
    { text: "中文 $(whoami)" },
    [{ role: "user", content: "问题" }],
    () => {},
    new AbortController().signal,
  );
  assert.equal(result, "中文 $(whoami) / 问题");
  const controller = new AbortController();
  const task = cliTurn(
    {
      kind: "custom",
      executable: process.execPath,
      arguments: JSON.stringify(["-e", "setInterval(()=>{},1000)"]),
    },
    {},
    [],
    () => {},
    controller.signal,
  );
  controller.abort();
  await assert.rejects(task, /停止/);
});

test("Codex CLI consumes JSON events and includes read-only ephemeral flags and context", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "mirror-codex-"));
  t.after(() => fs.rm(root, { recursive: true }));
  const file = path.join(root, "codex.js");
  await fs.writeFile(
    file,
    `let input='';process.stdin.setEncoding('utf8');process.stdin.on('data',d=>input+=d);process.stdin.on('end',()=>{const args=process.argv.slice(2);if(!args.includes('read-only')||!args.includes('--ephemeral')||!input.includes('第二轮'))process.exit(2);process.stdout.write(JSON.stringify({type:'item.completed',item:{type:'agent_message',text:'中文回复 🪞'}})+'\\n')});`,
  );
  const result = await cliTurn(
    { kind: "codex", executable: file, model: "test", effort: "low" },
    { text: "引用" },
    [
      { role: "user", content: "第一轮" },
      { role: "assistant", content: "回答" },
      { role: "user", content: "第二轮" },
    ],
    () => {},
    new AbortController().signal,
  );
  assert.equal(result, "中文回复 🪞");
});

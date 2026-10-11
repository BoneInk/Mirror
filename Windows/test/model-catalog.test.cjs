const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const fixtures = require("../../Tools/AgentSmoke/model-catalog-fixtures.json");
const { nativeModels, parseList, parseACP } = require("../electron/model-catalog.cjs");
const { listModels } = require("../electron/services.cjs");
async function fake(t, source) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "mirror-model-test-"));
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const executable = path.join(directory, "fake.cjs");
  await fs.writeFile(executable, source);
  return executable;
}
test("native model queries use documented commands without sending a question", async (t) => {
  for (const kind of ["claude", "pi", "codebuddy", "kimi", "cursor", "qoder", "opencode"]) {
    await t.test(kind, async (t) => {
      const data = JSON.stringify(fixtures[kind]);
      const executable = await fake(t, `
        const assert = require('node:assert/strict');
        const kind = ${JSON.stringify(kind)}, data = ${data};
        const args = process.argv.slice(2);
        function reply(value) {
          const raw = Buffer.from(JSON.stringify(value) + '\\n');
          const split = raw.indexOf(Buffer.from('🪞')) + 1;
          process.stdout.write(raw.subarray(0, split));
          setTimeout(() => process.stdout.write(raw.subarray(split)), 5);
        }
        if (['cursor','qoder','opencode'].includes(kind)) {
          assert.deepEqual(args, kind === 'opencode' ? ['models'] : ['--list-models']);
          let input=''; process.stdin.on('data',d=>input+=d);
          process.stdin.on('end',()=>{assert.equal(input,'');process.stdout.write(data)});
        } else {
          let stage=0;
          require('node:readline').createInterface({input:process.stdin}).on('line',line=>{
            const r=JSON.parse(line);assert.ok(!r.prompt && !r.message);
            if(kind==='claude') {
              assert.ok(args.includes('--safe-mode') && args.includes('--no-session-persistence'));
              assert.equal(r.type,'control_request');assert.equal(r.request.subtype,'initialize');
              reply({type:'control_response',response:{request_id:r.request_id,subtype:'success',response:data}});
            } else if(kind==='pi') {
              assert.ok(args.includes('--no-extensions'));
              assert.equal(r.type,'get_available_models');
              reply({type:'response',id:r.id,command:r.type,success:true,data});
            } else if(stage++===0) {
              assert.equal(r.method,'initialize');assert.deepEqual(r.params.clientCapabilities,{});
              reply({jsonrpc:'2.0',id:r.id,result:{protocolVersion:1}});
            } else if(r.method==='session/new') {
              assert.deepEqual(r.params.mcpServers,[]);
              // Ask the client for file access before returning metadata. It must decline.
              global.requestID=r.id;
              reply({jsonrpc:'2.0',id:'client-action',method:'fs/read_text_file',params:{path:'/private'}});
            } else {
              assert.equal(r.id,'client-action');assert.equal(r.error.code,-32601);
              reply({jsonrpc:'2.0',id:global.requestID,result:data});
            }
          });
        }
      `);
      const rows = await listModels({ kind, connection: "native", executable });
      assert.equal(rows.length, 2);
      if (kind === "claude") {
        assert.deepEqual(rows[0].efforts, ["low", "high"]);
        assert.deepEqual(rows[1].efforts, []);
        assert.equal(rows[0].isDefault, true);
      }
      if (kind === "pi") assert.deepEqual(rows.map((r) => r.id), ["one/same", "two/same"]);
      if (kind === "kimi") {
        assert.deepEqual(rows.map((r) => r.id), ["configured-key", "reasoning-key"]);
        assert.equal(rows[0].isDefault, true);
      }
    });
  }
});
test("text and structured catalogs preserve IDs, discard hidden rows and reject diagnostics", () => {
  assert.deepEqual(parseList(fixtures.opencode, "opencode").map((r) => r.id), ["provider/model-one", "other/model-two"]);
  assert.deepEqual(parseList(fixtures.qoder, "qoder").map((r) => r.id), ["auto", "byok:key"]);
  assert.equal(parseList(fixtures.cursor, "cursor")[1].name, "Sonnet🪞");
  assert.equal(parseList("byok:key: 模型🪞\n", "qoder")[0].id, "byok:key");
  assert.deepEqual(parseList(JSON.stringify({data:[{id:'one'},{id:'one'},{id:'hidden',hidden:true},{id:'disabled',is_enabled:false}]}), "qoder").map(r=>r.id), ['one']);
  assert.deepEqual(parseList('[]', 'qoder'), []);
  assert.throws(() => parseList("Please login first", "cursor"), /模型列表无法识别/);
  assert.throws(() => parseACP({ sessionId: "old" }, "kimi"), /未返回模型列表/);
});
test("queries reject CLI errors, malformed RPC, unavailable versions, oversized output and timeouts", async (t) => {
  for (const [source, kind, pattern] of [
    ['console.log("secret diagnostic");process.exit(2)', 'qoder', /查询失败/],
    ['process.stdin.on("data",()=>console.log(JSON.stringify({type:"control_response",response:{request_id:"mirror-models",subtype:"error",error:"private"}})))', 'claude', /无法识别/],
    ['process.stdout.write("x".repeat(2000001))', 'qoder', /大小限制/],
    ['process.stdin.resume();process.on("SIGTERM",()=>{});setInterval(()=>{},1000)', 'pi', /超时/],
  ]) {
    const executable = await fake(t, source);
    await assert.rejects(nativeModels({kind, executable}, {timeout:300}), pattern);
  }
  await assert.rejects(nativeModels({kind:'qoder',executable:'/does-not-exist'}), /未找到/);
});
test("UI enables only documented model-query routes", async () => {
  const { canQueryModels } = await import("../src/agent-availability.mjs");
  assert.equal(canQueryModels({kind:'claude',connection:'native'}), true);
  assert.equal(canQueryModels({kind:'claude',connection:'command'}), false);
  assert.equal(canQueryModels({kind:'workbuddy',connection:'workbuddy'}), false);
  assert.equal(canQueryModels({kind:'hermes',connection:'http'}), true);
});
test("default profiles are Codex and Claude Code while all presets remain available to add", () => {
  const { defaultProfiles, presets } = require("../electron/profiles.cjs");
  assert.deepEqual(defaultProfiles.map((p) => p.kind), ['codex', 'claude']);
  for (const kind of ['cursor','opencode','kimi','pi','codebuddy','qoder','workbuddy','qwenwork']) {
    assert.ok(presets.some((p) => p.kind === kind));
  }
});

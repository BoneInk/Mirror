const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const crypto = require("node:crypto");
const { EventEmitter } = require("node:events");
const { UpdateManager, selectRelease, compare, trustedURL, checksum } = require("../electron/updates.cjs");
const bytes = Buffer.from("MZ verified fixture installer");
function release(tag = "v1.3.5", kinds = ["x64-setup", "arm64-setup", "x64-portable"]) {
  return { tag_name: tag, draft: false, prerelease: false, assets: kinds.map((kind) => {
    const name = `Mirror-${tag.replace(/^v/, "")}-windows-${kind}.exe`;
    return { name, state: "uploaded", size: bytes.length, digest: "sha256:" + crypto.createHash("sha256").update(bytes).digest("hex"), browser_download_url: `https://github.com/BoneInk/Mirror/releases/download/${tag}/${name}` };
  }) };
}
async function fixture(t, patch = {}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "mirror-update-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const saved = {};
  const store = { read: async (key, fallback) => saved[key] ?? fallback, write: async (key, value) => { saved[key] = value; } };
  let launches = [], requests = [];
  const config = {
    root, store, currentVersion: "1.3.4", arch: "x64", platform: "win32", executable: path.join(root, "Mirror.exe"),
    fetcher: async (url) => { requests.push(url); return url.includes("api.github.com") ? Response.json([release()]) : new Response(bytes); },
    launcher: (...args) => { launches.push(args); const child = new EventEmitter(); child.unref = () => {}; queueMicrotask(() => child.emit("spawn")); return child; },
    ...patch,
  };
  return { manager: new UpdateManager(config), saved, launches, requests };
}
test("select the latest compatible stable installer, independent of release order and other platforms", () => {
  const draft = { ...release("v2.0.0"), draft: true }, prerelease = { ...release("v3.0.0"), prerelease: true };
  const releases = [release("v1.3.9"), release("v1.10.0"), draft, prerelease, release("v4.0.0", []), release("vbroken")];
  assert.equal(selectRelease(releases, "x64").tag_name, "v1.10.0");
  assert.match(selectRelease(releases, "arm64").installer.name, /arm64-setup/);
  assert.match(selectRelease(releases, "x64", true).installer.name, /x64-portable/);
  assert.equal(selectRelease(releases, "ia32"), null);
  assert.equal(compare("v1.3.5", "1.3.5.0"), 0);
  assert.equal(compare("1.3.10", "1.3.9"), 1);
});
test("download verification, deferred installation, restart and preference cancellation", async (t) => {
  const { manager, launches } = await fixture(t);
  await manager.check(true);
  assert.equal(manager.state.ready, true);
  assert.equal(launches.length, 1);
  assert.deepEqual(await fs.readFile(manager.state.installer), bytes);
  const script = Buffer.from(launches[0][1].at(-1), "base64").toString("utf16le");
  assert.match(script, /Wait-Process -Id/);
  assert.match(script, /\/S \/currentuser \/D=/);
  assert.match(script, /Copy-Item.*-Recurse/);
  await manager.preferences(false);
  await assert.rejects(fs.access(manager.marker));
  await manager.restart();
  await fs.access(manager.marker); await fs.access(manager.restartMarker);
});
test("manual checks bypass the daily limit; automatic checks and downloads respect opt-out", async (t) => {
  const { manager, requests } = await fixture(t);
  await manager.preferences(false); await manager.check(true);
  assert.equal(requests.length, 0);
  await manager.check(); assert.equal(requests.length, 1);
  assert.equal(manager.state.ready, false);
  await manager.download(); assert.equal(manager.state.ready, true);
  await assert.rejects(fs.access(manager.marker));
});
test("daily throttling and failed request do not erase a recoverable retry", async (t) => {
  const { manager, saved, requests } = await fixture(t, { currentVersion: "1.3.5" });
  await manager.check(true); await manager.check(true);
  assert.equal(requests.length, 1); assert.equal(manager.state.availableVersion, null);
  await manager.check(); assert.equal(requests.length, 2);
  const broken = await fixture(t, { fetcher: async () => new Response("rate limited", { status: 403 }) });
  await broken.manager.check(true);
  assert.match(broken.manager.state.error, /403/); assert.equal(broken.saved["update-check"], undefined);
  assert.ok(saved["update-check"]);
});
test("API rate limits fall back to a verified stable release manifest", async (t) => {
  const { manager, launches } = await fixture(t, { fetcher: async (url) => {
    if (url.includes("api.github.com")) return new Response("rate limited", { status: 403 });
    if (url.endsWith("Mirror-update.json")) return Response.json(release());
    return new Response(bytes);
  } });
  await manager.check(true);
  assert.equal(manager.state.error, null);
  assert.equal(manager.state.ready, true);
  assert.equal(launches.length, 1);
  const invalid = await fixture(t, { fetcher: async (url) => url.includes("api.github.com")
    ? new Response("rate limited", { status: 403 }) : Response.json({ ...release(), prerelease: true }) });
  await invalid.manager.check(true);
  assert.match(invalid.manager.state.error, /403/);
  assert.equal(invalid.launches.length, 0);
});
test("invalid checksum, truncated downloads and unexpected download origins never launch installers", async (t) => {
  for (const variant of ["digest", "truncated", "origin", "missing"]) {
    const candidate = release();
    if (variant === "digest") candidate.assets[0].digest = "sha256:" + "0".repeat(64);
    if (variant === "origin") candidate.assets[0].browser_download_url = "https://example.com/evil.exe";
    if (variant === "missing") delete candidate.assets[0].digest;
    const { manager, launches } = await fixture(t, { fetcher: async (url) => url.includes("api.github.com") ? Response.json([candidate]) : new Response(variant === "truncated" ? bytes.subarray(2) : bytes) });
    await manager.check(true);
    assert.equal(manager.state.ready, false, variant); assert.ok(manager.state.error, variant); assert.equal(launches.length, 0, variant);
  }
  assert.equal(trustedURL("https://github.com/Other/Mirror/releases/download/v1/a.exe"), false);
  assert.equal(trustedURL("https://github.com.evil/BoneInk/Mirror/releases/download/v1/a.exe"), false);
  assert.equal(checksum("a".repeat(64) + "  other.exe", "Mirror.exe"), null);
});

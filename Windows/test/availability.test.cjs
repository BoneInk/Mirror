const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const { discoverProfiles } = require("../electron/services.cjs");

test("missing local commands hide without confusing offline services with uninstalled agents", async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "mirror-discovery-"));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const cli = path.join(root, "fixture.cjs");
  const profiles = [
    { id: "local", kind: "custom", connection: "command", executable: cli },
    { id: "directory", connection: "native", executable: root },
    { id: "http", connection: "http", endpoint: "https://example.com/v1" },
    {
      id: "smartwork",
      connection: "smartwork",
      endpoint: "http://127.0.0.1:1",
    },
  ];
  const { defaultProfile, selectableProfiles } = await import(
    "../src/agent-availability.mjs"
  );
  const missing = await discoverProfiles(profiles);
  assert.equal(missing[0].availability, "missing");
  assert.equal(missing[1].availability, "missing");
  assert.deepEqual(
    selectableProfiles(profiles, missing).map((p) => p.id),
    ["http", "smartwork"],
  );
  assert.equal(defaultProfile(profiles, missing, "local"), undefined);
  assert.equal(defaultProfile(profiles, missing, "http").id, "http");
  assert.equal(
    defaultProfile(profiles.slice(0, 2), missing, "local"),
    undefined,
  );
  // Installation is a change in detected state, never a deletion of configuration.
  await fs.writeFile(cli, "process.exit(0)");
  const installed = await discoverProfiles(profiles);
  assert.equal(installed[0].availability, "available");
  assert.equal(defaultProfile(profiles, installed, "local").id, "local");
  assert.equal(profiles.length, 4);
});

// Run on a disposable Windows CI runner against the actual release installers.
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const { spawn } = require("node:child_process");
const assert = require("node:assert/strict");
const { installScript } = require("../electron/updates.cjs");
const { version } = require("../package.json");

async function run(command, args) {
  const child = spawn(command, args, { windowsHide: true, stdio: "pipe" });
  let output = "";
  child.stdout.on("data", (data) => { output += data; });
  child.stderr.on("data", (data) => { output += data; });
  const code = await new Promise((resolve, reject) => { child.once("exit", resolve); child.once("error", reject); });
  return { code, output };
}
async function main() {
  if (process.platform !== "win32") { console.log("Windows installation integration requires Windows; skipped on this host."); return; }
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "mirror-update ' space-"));
  const windows = process.env.SystemRoot || "C:\\Windows";
  const powershell = path.join(windows, "System32/WindowsPowerShell/v1.0/powershell.exe");
  const fixture = path.join(root, "old-Mirror.exe");
  const source = path.join(root, "fixture.cs");
  await fs.writeFile(source, `using System; using System.Reflection; [assembly:AssemblyProduct("Mirror")] [assembly:AssemblyFileVersion("1.0.0.0")] [assembly:AssemblyInformationalVersion("1.0.0")] class Program { static void Main() { System.Threading.Thread.Sleep(30000); } }`);
  const compiled = await run(path.join(windows, "Microsoft.NET/Framework64/v4.0.30319/csc.exe"), ["/nologo", "/target:winexe", `/out:${fixture}`, source]);
  assert.equal(compiled.code, 0, compiled.output);
  try {
    for (const portable of [true, false]) {
      const installer = path.resolve("release", `Mirror-${version}-windows-x64-${portable ? "portable" : "setup"}.exe`);
      await fs.access(installer);
      for (const mode of ["success", "unarmed", "rollback"]) {
        const directory = path.join(root, `${portable ? "portable" : "setup"}-${mode}`);
        await fs.mkdir(directory);
        const target = path.join(directory, "Mirror.exe");
        await fs.copyFile(fixture, target);
        const marker = path.join(root, `${path.basename(directory)}-armed`);
        if (mode !== "unarmed") await fs.writeFile(marker, "");
        const parent = spawn(target, [], { windowsHide: true, stdio: "ignore" });
        await new Promise((resolve, reject) => { parent.once("spawn", resolve); parent.once("error", reject); });
        const exited = new Promise((resolve) => parent.once("exit", resolve));
        let script = installScript({ parentPID: parent.pid, target, installer, portable, currentVersion: "1.0.0", nextVersion: version, marker, restart: path.join(root, "no-restart"), result: path.join(root, "failure.txt") });
        if (mode === "rollback") script = script.replace("  if ((Get-Item -LiteralPath $target).VersionInfo.ProductVersion", "  throw 'Injected final verification failure'\n  if ((Get-Item -LiteralPath $target).VersionInfo.ProductVersion");
        const helper = run(powershell, ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")]);
        try {
          await new Promise((resolve) => setTimeout(resolve, 300));
          assert.deepEqual(await fs.readFile(target), await fs.readFile(fixture), "Never replace a running app");
        } finally { parent.kill(); await exited; }
        const result = await helper;
        if (mode === "rollback") assert.notEqual(result.code, 0, result.output);
        else assert.equal(result.code, 0, result.output);
        if (mode === "success") assert.notDeepEqual(await fs.readFile(target), await fs.readFile(fixture));
        else assert.deepEqual(await fs.readFile(target), await fs.readFile(fixture), result.output);
        console.log(`Windows ${portable ? "portable" : "NSIS"} installation passed: ${mode}`);
      }
    }
  } finally { await fs.rm(root, { recursive: true, force: true }); }
}
main().catch((error) => { console.error(error); process.exitCode = 1; });

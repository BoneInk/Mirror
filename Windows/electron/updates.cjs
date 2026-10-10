const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const { spawn } = require("node:child_process");

const RELEASES = "https://api.github.com/repos/BoneInk/Mirror/releases?per_page=100";
function version(value) {
  if (typeof value !== "string" || !/^v?\d+\.\d+\.\d+(?:\.\d+)?$/.test(value)) return null;
  const parts = value.replace(/^v/, "").split(".").map(Number);
  return parts.every(Number.isSafeInteger) ? parts : null;
}
function compare(a, b) {
  const left = version(a), right = version(b);
  if (!left || !right) throw new Error("版本号无效。");
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    if ((left[i] || 0) !== (right[i] || 0)) return (left[i] || 0) > (right[i] || 0) ? 1 : -1;
  }
  return 0;
}
function trustedURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname === "github.com" && !url.username && !url.password && !url.port && !url.search && url.pathname.startsWith("/BoneInk/Mirror/releases/download/");
  } catch { return false; }
}
function selectRelease(releases, arch, portable = false) {
  if (!["x64", "arm64"].includes(arch)) return null;
  return releases.filter((r) => !r.draft && !r.prerelease && version(r.tag_name))
    .map((r) => ({ ...r, installer: r.assets?.find((a) => a.state === "uploaded" && a.name === `Mirror-${r.tag_name.replace(/^v/, "")}-windows-${arch}-${portable ? "portable" : "setup"}.exe`) }))
    .filter((r) => r.installer).sort((a, b) => compare(b.tag_name, a.tag_name))[0] || null;
}
function checksum(text, name) {
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^([a-fA-F0-9]{64})\s+\*?(.+)$/);
    if (match?.[2] === name) return match[1].toLowerCase();
  }
  return null;
}
const literal = (value) => `'${String(value).replaceAll("'", "''")}'`;

function installScript({ parentPID, target, installer, portable, currentVersion, nextVersion, marker, restart, result }) {
  const folder = path.win32.dirname(target);
  const backup = `${portable ? target : folder}.mirror-backup-${crypto.randomUUID()}`;
  return `
$ErrorActionPreference = 'Stop'
$target = ${literal(target)}
$installer = ${literal(installer)}
$backup = ${literal(backup)}
$folder = ${literal(folder)}
$armed = ${literal(marker)}
$restart = ${literal(restart)}
$result = ${literal(result)}
$backedUp = $false
Wait-Process -Id ${Number(parentPID)} -ErrorAction SilentlyContinue
if (!(Test-Path -LiteralPath $armed)) { exit 0 }
try {
  $package = (Get-Item -LiteralPath $installer).VersionInfo
  if ($package.ProductName -ne 'Mirror' -or $package.ProductVersion -ne ${literal(nextVersion)}) { throw 'Invalid Mirror installer identity' }
  $current = (Get-Item -LiteralPath $target).VersionInfo.ProductVersion
  if ($current -ne ${literal(currentVersion)}) { exit 0 }
  ${portable ? `Move-Item -LiteralPath $target -Destination $backup
  $backedUp = $true
  Copy-Item -LiteralPath $installer -Destination $target` : `Copy-Item -LiteralPath $folder -Destination $backup -Recurse
  $backedUp = $true
  $process = Start-Process -FilePath $installer -ArgumentList ('/S /currentuser /D=' + $folder) -Wait -PassThru
  if ($process.ExitCode -ne 0) { throw 'Installer failed' }`}
  $installedVersion = (Get-Item -LiteralPath $target).VersionInfo.ProductVersion
  if ($installedVersion -ne ${literal(nextVersion)}) { throw ('Installed version does not match: ' + $installedVersion) }
  Remove-Item -LiteralPath $backup -Recurse -Force
  $backedUp = $false
  Remove-Item -LiteralPath $armed -Force
  if (Test-Path -LiteralPath $result) { Remove-Item -LiteralPath $result -Force }
  if (Test-Path -LiteralPath $restart) { Start-Process -FilePath $target }
} catch {
  $failure = $_.Exception.Message
  if ($backedUp) {
    try {
      ${portable ? `if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
      Move-Item -LiteralPath $backup -Destination $target` : `if (Test-Path -LiteralPath $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
      Move-Item -LiteralPath $backup -Destination $folder`}
    } catch { $failure += '; rollback: ' + $_.Exception.Message }
  }
  $failure | Set-Content -LiteralPath $result -Encoding UTF8
  [Console]::Error.WriteLine($failure)
  if ((Test-Path -LiteralPath $restart) -and (Test-Path -LiteralPath $target)) { Start-Process -FilePath $target }
  exit 1
}
`;
}

class UpdateManager {
  constructor({ store, root, currentVersion, arch = process.arch, portablePath, executable = process.execPath, platform = process.platform, fetcher = fetch, notify = () => {}, launcher = spawn }) {
    Object.assign(this, { store, root, currentVersion, arch, portablePath, executable, platform, fetcher, notify, launcher });
    this.state = { status: "每天自动检查，更新将在退出后安装。", currentVersion, busy: false, ready: false };
    this.enabled = true;
  }
  emit(patch) { this.state = { ...this.state, ...patch }; this.notify(this.state); return this.state; }
  async preferences(enabled) {
    this.enabled = enabled !== false;
    if (this.marker) {
      if (this.enabled) await fs.writeFile(this.marker, "");
      else await fs.rm(this.marker, { force: true });
      if (this.state.ready) this.emit({ status: this.enabled ? "更新已就绪，退出后自动安装。" : "自动安装已暂停，可点击立即重启更新。" });
    }
  }
  async json(url) {
    const response = await this.fetcher(url, { headers: { Accept: "application/vnd.github+json", "User-Agent": "Mirror-Update" }, signal: AbortSignal.timeout(30000) });
    if (!response.ok) throw new Error(`GitHub 暂时不可用（${response.status}），请稍后重试。`);
    return response.json();
  }
  async check(automatic = false) {
    if (this.state.busy || this.state.ready) return this.state;
    if (automatic && (this.platform !== "win32" || !this.enabled)) return this.state;
    this.emit({ busy: true });
    try {
      const saved = await this.store.read("update-check", {});
      if (automatic && Date.now() - (saved.checkedAt || 0) < 86400000) return this.state;
      this.emit({ error: null, status: "正在检查更新…" });
      const releases = await this.json(RELEASES);
      const release = selectRelease(releases, this.arch, !!this.portablePath);
      if (!release) throw new Error("没有找到适合此 Windows 架构的安装包。");
      await this.store.write("update-check", { checkedAt: Date.now() });
      this.release = compare(release.tag_name, this.currentVersion) > 0 ? release : null;
      this.emit({ availableVersion: this.release?.tag_name || null, status: this.release ? "发现新版本。" : "Mirror 已是最新版本。", lastChecked: Date.now() });
      if (automatic && this.release && this.enabled) await this.prepare();
    } catch (error) { this.emit({ error: error.message, status: "无法检查更新。" }); }
    finally { this.emit({ busy: false }); }
    return this.state;
  }
  async download() {
    if (this.state.busy || !this.release || this.state.ready) return this.state;
    this.emit({ busy: true, error: null });
    try { await this.prepare(); }
    catch (error) { this.emit({ error: error.message, status: "无法准备更新，当前安装保持不变。" }); }
    finally { this.emit({ busy: false }); }
    return this.state;
  }
  async prepare() {
    const asset = this.release.installer;
    if (!trustedURL(asset.browser_download_url) || !Number.isSafeInteger(asset.size) || asset.size <= 0 || asset.size > 2000000000) throw new Error("安装包信息无效。");
    let expected = /^sha256:([a-fA-F0-9]{64})$/.exec(asset.digest || "")?.[1]?.toLowerCase();
    if (!expected) {
      const sums = this.release.assets.find((a) => a.name === "SHA256SUMS.txt");
      if (!sums || !trustedURL(sums.browser_download_url)) throw new Error("Release 缺少有效的 SHA-256 校验信息。");
      const response = await this.fetcher(sums.browser_download_url, { signal: AbortSignal.timeout(30000) });
      if (!response.ok) throw new Error("无法下载校验信息。");
      expected = checksum(await response.text(), asset.name);
      if (!expected) throw new Error("Release 缺少此安装包的校验信息。");
    }
    await fs.mkdir(this.root, { recursive: true });
    const directory = await fs.mkdtemp(path.join(this.root, "update-"));
    const installer = path.join(directory, asset.name);
    const partial = installer + ".partial";
    this.emit({ status: "正在下载并校验更新…", progress: 0 });
    const response = await this.fetcher(asset.browser_download_url, { signal: AbortSignal.timeout(600000) });
    if (!response.ok || !response.body) throw new Error("安装包下载失败。");
    const file = await fs.open(partial, "wx");
    const hash = crypto.createHash("sha256");
    let received = 0, lastProgress = 0;
    try {
      for await (const chunk of response.body) {
        received += chunk.length;
        if (received > asset.size) throw new Error("安装包大小与 Release 不符。");
        hash.update(chunk); await file.writeFile(chunk);
        const progress = Math.floor(received / asset.size * 100);
        if (progress !== lastProgress) { lastProgress = progress; this.emit({ progress }); }
      }
      if (received !== asset.size || hash.digest("hex") !== expected) throw new Error("安装包校验失败，未进行安装。");
    } catch (error) { await file.close(); await fs.rm(partial, { force: true }); throw error; }
    finally { await file.close().catch(() => {}); }
    await fs.rename(partial, installer);
    this.emit({ installer });
    if (this.platform !== "win32") throw new Error("自动安装仅在 Windows 上运行。");
    const target = this.portablePath || this.executable;
    try { await fs.access(path.dirname(target), fs.constants.W_OK); }
    catch { this.emit({ status: "安装目录不可写，请打开安装包手动更新。" }); return; }
    this.marker = path.join(directory, "install-on-exit");
    this.restartMarker = path.join(directory, "restart");
    const script = installScript({ parentPID: process.pid, target, installer, portable: !!this.portablePath, currentVersion: this.currentVersion, nextVersion: this.release.tag_name.replace(/^v/, ""), marker: this.marker, restart: this.restartMarker, result: path.join(this.root, "last-install-error.txt") });
    if (this.enabled) await fs.writeFile(this.marker, "");
    const powershell = path.join(process.env.SystemRoot || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
    const child = this.launcher(powershell, ["-NoProfile", "-NonInteractive", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")], { detached: true, stdio: "ignore", windowsHide: true });
    await new Promise((resolve, reject) => { child.once("spawn", resolve); child.once("error", reject); });
    child.unref();
    this.emit({ ready: true, status: this.enabled ? "更新已就绪，退出后自动安装。" : "更新已就绪，可点击立即重启更新。" });
  }
  async restart() {
    if (!this.state.ready) throw new Error("更新尚未就绪。");
    await fs.writeFile(this.marker, ""); await fs.writeFile(this.restartMarker, "");
  }
}
module.exports = { UpdateManager, selectRelease, version, compare, checksum, trustedURL, installScript };

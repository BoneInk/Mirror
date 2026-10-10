import Foundation

enum MacUpdateInstaller {
    struct Staged { let armed: URL; let restart: URL }

    static func run(_ command: String, _ arguments: [String], log: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command); process.arguments = arguments
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        try handle.seekToEnd()
        process.standardOutput = handle; process.standardError = handle
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SoftwareUpdateError.message("Unable to prepare the update. The current application is unchanged.") }
    }

    static func stage(dmg: URL, directory: URL, destination: URL, version: String) throws -> Staged {
        let fm = FileManager.default
        let mount = directory.appendingPathComponent("mount")
        let log = directory.appendingPathComponent("install.log")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, dmg.path], log: log)
        defer { try? run("/usr/bin/hdiutil", ["detach", mount.path], log: log) }
        let app = mount.appendingPathComponent("Mirror.app")
        let staged = directory.appendingPathComponent("Mirror.app")
        try run("/usr/bin/ditto", [app.path, staged.path], log: log)
        try validate(app: staged, version: version)
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path], log: log)
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        try run("/usr/bin/lipo", [staged.appendingPathComponent("Contents/MacOS/Mirror").path, "-verify_arch", architecture], log: log)
        try fm.copyItem(at: destination.appendingPathComponent("Contents/Info.plist"), to: directory.appendingPathComponent("current.plist"))
        let armed = directory.appendingPathComponent("install-on-exit")
        let restart = directory.appendingPathComponent("restart")
        let helper = directory.appendingPathComponent("install.sh")
        try helperScript.write(to: helper, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), staged.path, destination.path, armed.path, restart.path, version]
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        process.standardOutput = handle; process.standardError = handle; process.standardInput = FileHandle.nullDevice
        try process.run()
        try? handle.close()
        return Staged(armed: armed, restart: restart)
    }

    static func validate(app: URL, version: String) throws {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        guard plist?["CFBundleIdentifier"] as? String == "com.local.mirror",
              plist?["CFBundleShortVersionString"] as? String == version,
              plist?["CFBundleExecutable"] as? String == "Mirror" else {
            throw SoftwareUpdateError.message("The release installer is invalid.")
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        if let minimum = plist?["LSMinimumSystemVersion"] as? String,
           let required = ReleaseVersion(minimum.split(separator: ".").count == 2 ? minimum + ".0" : minimum),
           let current = ReleaseVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"), required > current {
            throw SoftwareUpdateError.message("This update requires a newer macOS version.")
        }
    }

    // Quoted positional arguments keep spaces and shell metacharacters in paths inert.
    // Keep the backup on failure; a successful install removes it only after verification.
    static let helperScript = """
    #!/bin/sh
    set -eu
    parent="$1"; staged="$2"; target="$3"; armed="$4"; restart="$5"; version="$6"
    while /bin/kill -0 "$parent" 2>/dev/null; do /bin/sleep 1; done
    [ -f "$armed" ] || exit 0
    incoming="${target%.app}.update-$$.app"
    backup="${target%.app}.backup-$$.app"
    result="${staged%/Mirror.app}/../last-install-error.txt"
    rollback() {
      failure="$?"
      if [ -d "$backup" ]; then
        [ ! -d "$target" ] || /bin/mv "$target" "$incoming.failed"
        /bin/mv "$backup" "$target"
      fi
      if [ "$failure" -ne 0 ]; then
        /usr/bin/printf '%s\n' 'Automatic installation failed; the old application was retained or restored when possible.' > "$result"
        if [ -f "$restart" ] && [ -d "$target" ]; then /usr/bin/open "$target"; fi
      fi
    }
    trap rollback EXIT HUP INT TERM
    /usr/bin/ditto "$staged" "$incoming"
    /usr/bin/codesign --verify --deep --strict "$incoming"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$incoming/Contents/Info.plist")" = 'com.local.mirror' ]
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$incoming/Contents/Info.plist")" = "$version" ]
    # If another updater or manual installation already installed a newer build, keep it.
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")" = "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$staged/../current.plist")" ] || exit 0
    /bin/mv "$target" "$backup"
    /bin/mv "$incoming" "$target"
    /usr/bin/codesign --verify --deep --strict "$target"
    trap - EXIT HUP INT TERM
    /bin/rm -rf "$backup"
    /bin/rm -f "$armed"
    /bin/rm -f "$result"
    if [ -f "$restart" ]; then /usr/bin/open "$target"; fi
    """
}

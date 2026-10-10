import AppKit

NSApplication.shared.setActivationPolicy(.accessory)
Task { @MainActor in
    do {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("Mirror Codex 路径-" + UUID().uuidString)
        defer { try? manager.removeItem(at: root) }
        let app = root.appendingPathComponent("Renamed App.app")
        let legacy = app.appendingPathComponent("Contents/Resources/codex")
        let nested = app.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex")
        let wrapper = app.appendingPathComponent("Contents/Resources/codex-cli/bin/codex")
        let bin = root.appendingPathComponent("bin")
        let cli = bin.appendingPathComponent("codex")
        func install(_ url: URL) throws {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        @MainActor func resolve() -> URL? { CodexAppServer.executableURL(appURL: app, searchPaths: ["", bin.path]) }
        precondition(resolve() == nil)
        try install(cli)
        precondition(CodexAppServer.executableURL(appURL: nil, searchPaths: [bin.path]) == cli)
        precondition(resolve() == cli)
        try install(wrapper)
        precondition(resolve() == wrapper)
        try install(nested)
        precondition(resolve() == nested)
        // Finder's minimal PATH must not hide a bundled CLI.
        precondition(CodexAppServer.executableURL(appURL: app, searchPaths: ["/usr/bin", "/bin"]) == nested)
        try install(legacy)
        precondition(resolve() == legacy)
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: legacy.path)
        precondition(resolve() == nested)
        print("PASS: legacy/nested/wrapper bundles, executable checks, CLI fallback, renamed app, Unicode/spaces, Finder PATH")

        if CommandLine.arguments.contains("--live") {
            guard let executable = CodexAppServer.executableURL() else {
                throw CodexConnectionError(message: "Installed Codex CLI was not discovered")
            }
            print("Discovered installed CLI: \(executable.path)")
            let server = CodexAppServer()
            defer { server.close() }
            try await server.connect()
            let account = try await server.request("account/read", ["refreshToken": false])
            precondition(account["account"] is [String: Any], "Codex account is not signed in")
            let models = try await server.request("model/list", ["limit": 1])
            precondition(!(models["data"] as? [[String: Any]] ?? []).isEmpty, "Model list is empty")
            print("PASS: installed app-server initialization, signed-in account, model list; no turns submitted")
        }
        exit(0)
    } catch {
        print("FAIL: \(error.localizedDescription)")
        exit(1)
    }
}
NSApplication.shared.run()

import AppKit

struct CodexConnectionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// A private stdio connection: no listening port and no credentials copied into Mirror.
@MainActor
final class CodexAppServer {
    var onNotification: ((String, [String: Any]) -> Void)?
    var onDisconnect: ((String) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private let writer = DispatchQueue(label: "Mirror.Codex.writer")
    private var generation = UUID()

    static func executableURL() -> URL? {
        let manager = FileManager.default
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
            let bundled = app.appendingPathComponent("Contents/Resources/codex")
            if manager.isExecutableFile(atPath: bundled.path) { return bundled }
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
            + ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]
        return paths.filter { !$0.isEmpty }.map { URL(fileURLWithPath: $0).appendingPathComponent("codex") }
            .first { manager.isExecutableFile(atPath: $0.path) }
    }

    func connect(executable: URL? = nil) async throws {
        guard process == nil else { return }
        guard let executable = executable ?? Self.executableURL() else {
            throw CodexConnectionError(message: "未找到 Codex。请先安装并登录 Codex 应用或 Codex CLI。")
        }
        generation = UUID()
        let token = generation
        let process = Process()
        let stdin = Pipe(), stdout = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        // Finder-launched applications have a minimal PATH. Include the bundled tool directory.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                if data.isEmpty { self.disconnected("Codex 连接已关闭，请重新发送。") }
                else { self.consume(data) }
            }
        }
        self.process = process
        do {
            try process.run()
            _ = try await request("initialize", ["clientInfo": ["name": "mirror", "title": "Mirror", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1"]])
            try send(["method": "initialized", "params": [:]])
        } catch {
            close()
            throw error
        }
    }

    func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        guard process?.isRunning == true else { throw CodexConnectionError(message: "Codex 尚未连接。") }
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeouts[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(45))
                guard !Task.isCancelled, let self else { return }
                self.timeouts.removeValue(forKey: id)
                self.pending.removeValue(forKey: id)?.resume(throwing: CodexConnectionError(message: "Codex 连接超时，请重试。"))
            }
            do { try send(["id": id, "method": method, "params": params]) }
            catch { resolve(id: id, result: .failure(error)) }
        }
    }

    private func send(_ message: [String: Any]) throws {
        guard let input else { throw CodexConnectionError(message: "Codex 连接已关闭。") }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(10)
        let token = generation
        writer.async { [weak self] in
            do { try input.write(contentsOf: data) }
            catch {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.disconnected("无法写入 Codex 连接，请重试。")
                }
            }
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let method = message["method"] as? String {
                if let id = message["id"] {
                    // This reading assistant does not silently approve tools or leave server requests hanging.
                    let result: [String: Any]?
                    switch method {
                    case "item/commandExecution/requestApproval", "item/fileChange/requestApproval": result = ["decision": "decline"]
                    case "item/tool/requestUserInput": result = ["answers": [:]]
                    case "mcpServer/elicitation/request": result = ["action": "decline"]
                    default: result = nil
                    }
                    if let result { try? send(["id": id, "result": result]) }
                    else { try? send(["id": id, "error": ["code": -32601, "message": "Unsupported by Mirror chat"]]) }
                    onNotification?("mirror/actionUnavailable", [:])
                } else {
                    onNotification?(method, message["params"] as? [String: Any] ?? [:])
                }
            } else if let id = message["id"] as? Int {
                if let error = message["error"] as? [String: Any] {
                    resolve(id: id, result: .failure(CodexConnectionError(message: error["message"] as? String ?? "Codex 请求失败。")))
                } else { resolve(id: id, result: .success(message["result"] as? [String: Any] ?? [:])) }
            }
        }
    }

    private func resolve(id: Int, result: Result<[String: Any], Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func disconnected(_ message: String) {
        guard process != nil else { return }
        close()
        onDisconnect?(message)
    }

    func close() {
        generation = UUID()
        output?.readabilityHandler = nil
        try? input?.close()
        if let process, process.isRunning { process.terminate() }
        output = nil
        input = nil
        process = nil
        buffer.removeAll()
        for id in Array(pending.keys) {
            resolve(id: id, result: .failure(CodexConnectionError(message: "Codex 连接已关闭。")))
        }
    }
}

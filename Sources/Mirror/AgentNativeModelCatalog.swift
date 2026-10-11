import Foundation
import Darwin

/// Native metadata commands only. Never sends a user prompt or accepts client tool requests.
@MainActor
enum AgentNativeModelCatalog {
    static func supports(_ kind: AgentKind) -> Bool {
        [.claude, .codebuddy, .cursor, .opencode, .pi, .kimi, .qoder].contains(kind)
    }
    static func failure(_ message: String = "模型列表无法识别，请检查 CLI 版本与登录；仍可手动填写。") -> CodexConnectionError {
        CodexConnectionError(message: message)
    }
    static func fetch(_ profile: AgentProfile, timeout: TimeInterval = 15) async throws -> [AgentModelOption] {
        guard supports(profile.kind), let executable = AgentConfigurationStore.executable(for: profile) else {
            throw failure("未找到智能体命令，请在设置中配置路径。")
        }
        let rpc = [.claude, .codebuddy, .pi, .kimi].contains(profile.kind)
        let acp = [.codebuddy, .kimi].contains(profile.kind)
        // ACP exposes models in session/new. Isolate the empty metadata session from documents.
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("MirrorModels-\(UUID())")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let child = Process(), input = Pipe(), output = Pipe()
        switch profile.kind {
        case .claude:
            child.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--tools", "", "--strict-mcp-config", "--safe-mode", "--no-session-persistence"]
        case .codebuddy: child.arguments = ["--acp", "--tools", "", "--strict-mcp-config"]
        case .kimi: child.arguments = ["acp"]
        case .pi: child.arguments = ["--mode", "rpc", "--no-session", "--no-tools", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-context-files"]
        case .opencode: child.arguments = ["models"]
        default: child.arguments = ["--list-models"]
        }
        child.executableURL = executable; child.currentDirectoryURL = workspace
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ([executable.deletingLastPathComponent().path] + AgentConfigurationStore.executableDirectories).joined(separator: ":")
        environment["NO_COLOR"] = "1"; environment["TERM"] = "dumb"
        if profile.kind == .opencode { environment["OPENCODE_DISABLE_DEFAULT_PLUGINS"] = "true" }
        child.environment = environment
        try Task.checkCancellation()
        try child.run()
        func stop() {
            if child.isRunning {
                child.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                }
            }
        }
        let deadline = Task { @MainActor in
            try await Task.sleep(for: .seconds(timeout))
            stop()
        }
        defer { deadline.cancel(); stop(); try? input.fileHandleForWriting.close() }
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                while true {
                    let data = output.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    continuation.yield(data)
                }
                child.waitUntilExit()
                if child.terminationStatus == 0 { continuation.finish() }
                else { continuation.finish(throwing: CodexConnectionError(message: "模型查询失败或超时，请检查 CLI 版本与登录；仍可手动填写。")) }
            }
            continuation.onTermination = { _ in
                if child.isRunning { child.terminate() }
            }
        }
        func send(_ request: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: request); data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        if acp {
            try send(["jsonrpc": "2.0", "id": "mirror-initialize", "method": "initialize",
                      "params": ["protocolVersion": 1, "clientCapabilities": [:], "clientInfo": ["name": "Mirror", "version": "1"]]])
        } else if profile.kind == .claude {
            try send(["type": "control_request", "request_id": "mirror-models", "request": ["subtype": "initialize"]])
        } else if profile.kind == .pi {
            try send(["id": "mirror-models", "type": "get_available_models"])
        } else { try input.fileHandleForWriting.close() }
        var buffer = Data(), size = 0
        for try await chunk in stream {
            try Task.checkCancellation()
            size += chunk.count; guard size <= 2_000_000 else { throw failure("模型列表超出大小限制。") }
            buffer.append(chunk)
            if !rpc { continue }
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer.prefix(upTo: end)); buffer.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if acp {
                    // No filesystem, terminal, permission, or authentication action is performed.
                    if object["method"] != nil, let id = object["id"] {
                        try send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Metadata client does not support client actions"]])
                        continue
                    }
                    let id = object["id"] as? String
                    guard id == "mirror-initialize" || id == "mirror-models" else { continue }
                    guard object["error"] == nil, let result = object["result"] as? [String: Any] else { throw failure() }
                    if id == "mirror-initialize" {
                        try send(["jsonrpc": "2.0", "id": "mirror-models", "method": "session/new", "params": ["cwd": workspace.path, "mcpServers": []]])
                    } else { return try parseACP(result, kind: profile.kind) }
                } else if profile.kind == .claude, object["type"] as? String == "control_response",
                          let response = object["response"] as? [String: Any], response["request_id"] as? String == "mirror-models" {
                    guard response["subtype"] as? String == "success", let result = response["response"] as? [String: Any],
                          let rows = result["models"] as? [[String: Any]] else { throw failure() }
                    return unique(rows.compactMap { row in
                        guard let id = row["value"] as? String, !id.isEmpty else { return nil }
                        return AgentModelOption(id: id, name: row["displayName"] as? String ?? id, isDefault: id == "default",
                            efforts: row["supportedEffortLevels"] as? [String] ?? (row["supportsEffort"] as? Bool == false ? [] : nil))
                    })
                } else if profile.kind == .pi, object["type"] as? String == "response",
                          object["id"] as? String == "mirror-models", object["command"] as? String == "get_available_models" {
                    guard object["success"] as? Bool == true, let result = object["data"] as? [String: Any],
                          let rows = result["models"] as? [[String: Any]] else { throw failure() }
                    return unique(rows.compactMap { row in
                        guard let id = row["id"] as? String, let provider = row["provider"] as? String, !id.isEmpty, !provider.isEmpty else { return nil }
                        return AgentModelOption(id: provider + "/" + id, name: row["name"] as? String ?? id,
                            isDefault: false, efforts: row["reasoning"] as? Bool == false ? [] : nil)
                    })
                }
            }
        }
        try Task.checkCancellation()
        guard !rpc, let text = String(data: buffer, encoding: .utf8) else { throw failure() }
        return try parseList(text, kind: profile.kind)
    }

    static func unique(_ options: [AgentModelOption]) -> [AgentModelOption] {
        var seen = Set<String>(); return options.filter { seen.insert($0.id).inserted }
    }
    static func parseACP(_ result: [String: Any], kind: AgentKind) throws -> [AgentModelOption] {
        var rows: [[String: Any]]?, current: String?
        if let config = (result["configOptions"] as? [[String: Any]])?.first(where: {
            ($0["category"] as? String == "model" || $0["id"] as? String == "model") && $0["type"] as? String == "select"
        }), let values = config["options"] as? [[String: Any]] {
            rows = values.flatMap { ($0["options"] as? [[String: Any]]) ?? [$0] }; current = config["currentValue"] as? String
        } else if let models = result["models"] as? [String: Any] {
            rows = models["availableModels"] as? [[String: Any]]; current = models["currentModelId"] as? String
        }
        guard let rows else { throw failure("此 CLI 版本未返回模型列表，可更新 CLI 或手动填写。") }
        func cliID(_ id: String) -> String { kind == .kimi && id.hasSuffix(",thinking") ? String(id.dropLast(9)) : id }
        return unique(rows.compactMap { row in
            guard let raw = row["modelId"] as? String ?? row["value"] as? String, !raw.isEmpty else { return nil }
            let id = cliID(raw)
            let name = row["name"] as? String ?? id
            return AgentModelOption(id: id, name: kind == .kimi ? name.replacingOccurrences(of: " (thinking)", with: "") : name,
                isDefault: current.map(cliID) == id, efforts: nil)
        })
    }

    /// CLI output varies by version: accept JSON catalogs and explicit ID rows, never invent IDs from display names.
    static func parseList(_ output: String, kind: AgentKind) throws -> [AgentModelOption] {
        let text = output.replacingOccurrences(of: "\u{1B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        if let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) {
            let rows = json as? [Any] ?? (json as? [String: Any])?["models"] as? [Any] ?? (json as? [String: Any])?["data"] as? [Any]
            if let rows { return unique(rows.compactMap { value in
                if let id = value as? String, !id.isEmpty { return AgentModelOption(id: id, name: id, isDefault: false, efforts: nil) }
                guard let row = value as? [String: Any], row["hidden"] as? Bool != true, row["is_enabled"] as? Bool != false,
                      let id = row["id"] as? String ?? row["modelId"] as? String, !id.isEmpty else { return nil }
                return AgentModelOption(id: id, name: row["displayName"] as? String ?? row["display_name"] as? String ?? row["name"] as? String ?? id,
                    isDefault: row["isDefault"] as? Bool ?? false, efforts: nil)
            }) }
        }
        var options: [AgentModelOption] = []
        for line in text.components(separatedBy: .newlines) {
            var row = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if row.hasPrefix("|") || row.hasPrefix("│") { row.removeFirst(); row = row.trimmingCharacters(in: .whitespaces) }
            if row.hasPrefix("- ") || row.hasPrefix("• ") || row.hasPrefix("* ") { row = String(row.dropFirst(2)) }
            let pattern = kind == .opencode ? "^([A-Za-z0-9_.:-]+/[^\\s]+)$" : "^([A-Za-z0-9_][A-Za-z0-9_./:@+-]*)(?:\\s+-\\s+|:\\s+|\\s*[|│]\\s*|\\s{2,}|$)(.*)$"
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: row, range: NSRange(row.startIndex..., in: row)),
                  let range = Range(match.range(at: 1), in: row) else { continue }
            let id = String(row[range])
            guard !["id", "model", "models", "name", "available", "available-models", "error", "warning"].contains(id.lowercased()) else { continue }
            let label = match.numberOfRanges > 2 ? Range(match.range(at: 2), in: row).map { String(row[$0]).trimmingCharacters(in: .whitespaces) } : nil
            options.append(AgentModelOption(id: id, name: label.flatMap { $0.isEmpty ? nil : $0 } ?? id, isDefault: false, efforts: nil))
        }
        let result = unique(options)
        guard !result.isEmpty else { throw failure() }
        return result
    }
}

import AppKit

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
NSApplication.shared.setActivationPolicy(.prohibited)
Task { @MainActor in
    do {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let port = CommandLine.arguments[2]
        let defaults = UserDefaults(suiteName: "MirrorAgentSmoke-\(UUID())")!
        let store = AgentConfigurationStore(defaults: defaults)
        let user = CodexChatMessage(id: "u", isUser: true, text: "问题🪞")
        for kind in [AgentKind.claude, .codebuddy, .cursor, .kimi, .qoder, .opencode, .pi, .custom] {
            var profile = AgentProfile.preset(kind)
            profile.executable = directory.appendingPathComponent(kind.rawValue).path
            if kind == .custom { profile.connection = .command }
            var text = ""
            try await AgentTransport().run(profile: profile, messages: [user], directory: directory) { text = $0 }
            check(text == "你好🪞", "CLI parser failed: \(kind) \(text)")
        }
        check(store.profiles.count == AgentKind.allCases.count - 1, "All provider presets are present")
        store.delete(store.profiles.first { $0.kind == .workbuddy }!)
        check(!AgentConfigurationStore(defaults: defaults).profiles.contains { $0.kind == .workbuddy }, "Removed presets stay removed")
        let legacyDefaults = UserDefaults(suiteName: "MirrorMigration-\(UUID())")!
        legacyDefaults.set(try JSONEncoder().encode([AgentProfile.preset(.claude)]), forKey: "mirrorAgentProfiles")
        check(AgentConfigurationStore(defaults: legacyDefaults).profiles.contains { $0.kind == .qwenwork }, "New providers migrate into existing settings")
        check(AgentConfigurationStore.isSmartworkHealth(Data(#"{"ok":true,"name":"smartwork-agent-runtime","protocol":"smartwork-agent-turns-v1"}"#.utf8)), "Smartwork health protocol")
        check(!AgentConfigurationStore.isSmartworkHealth(Data(#"{"ok":true}"#.utf8)), "Reject unrelated health endpoints")
        for kind in [AgentKind.smartwork, .workbuddy] {
            var native = AgentProfile.preset(kind); native.id = "fixture-" + UUID().uuidString
            native.endpoint = "http://127.0.0.1:\(port)/" + (kind == .workbuddy ? "wb" : "sw")
            if kind == .smartwork { native.model = "fixture::model" }
            var answer = ""
            try await AgentTransport(credential: { _ in "fixture-only" }).run(profile: native, messages: [user], directory: directory) { answer = $0 }
            check(answer == "你好🪞", "Native HTTP protocol: \(kind)")
            for failure in (kind == .smartwork ? ["fail", "truncated"] : ["offline", "conflict", "permission"]) {
                var broken = native; broken.endpoint += "/" + failure
                do {
                    try await AgentTransport(credential: { _ in "fixture-only" }).run(profile: broken, messages: [user], directory: directory) { _ in }
                    fatalError("Expected protocol failure: \(kind) / \(failure)")
                } catch {}
            }
        }
        var profile = AgentProfile.preset(.deepseekHarness)
        profile.id = "fixture-" + UUID().uuidString // Never read a real profile's Keychain entry.
        profile.endpoint = "http://127.0.0.1:\(port)/v1";profile.model = "fixture"
        store.save(profile);store.selectedID = profile.id
        check(AgentConfigurationStore(defaults: defaults).selected == profile, "Configuration persistence")
        for prefix in ["v1", "json"] {
            profile.endpoint = "http://127.0.0.1:\(port)/\(prefix)"
            var text = ""
            try await AgentTransport().run(profile: profile, messages: [user], directory: directory) { text = $0 }
            check(text == "你好🪞", "HTTP response")
        }
        for prefix in ["fail", "redirect", "truncated"] {
            profile.endpoint = "http://127.0.0.1:\(port)/\(prefix)"
            do {
                try await AgentTransport().run(profile: profile, messages: [user], directory: directory) { _ in }
                fatalError("Expected \(prefix) failure")
            } catch { }
        }
        var bad = profile;bad.endpoint = "https://secret@example.com/v1"
        check(bad.validation != nil, "Credential URL rejected")
        bad.connection = .command;bad.executable = "/missing";bad.arguments = "--shell"
        check(bad.validation != nil, "Invalid argument array")
        let memory = CodexMemoryStore(url: directory.appendingPathComponent("memory.json"), defaults: defaults)
        let source = "来源🪞"
        let selection = ReferenceSelection(text: source, sourceAnchor: CodexTextAnchor.capture(in: source, range: NSRange(location: 0, length: (source as NSString).length)))
        let reference = DocumentReference(text: source, title: "测试", fileURL: directory.appendingPathComponent("test.md"), selection: selection)
        var custom = AgentProfile.preset(.custom);custom.connection = .command;custom.executable = directory.appendingPathComponent("custom").path
        let chat = CodexChatModel(reference: reference, directory: directory, memory: memory)
        chat.selectAgent(custom);chat.draft = "问题🪞";chat.send()
        while chat.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        check(chat.error == nil && chat.messages.count == 2, "Chat transport integrated")
        check(memory.records.first?.agentProfile == custom, "Memory includes provider snapshot")
        chat.selectAgent(.preset(.claude));check(chat.agent == custom, "Provider cannot change within conversation")
        let record = memory.records[0]
        let restored = CodexChatModel(reference: reference, directory: directory, memory: memory, restored: record)
        check(restored.agent == custom && restored.messages.count == 2, "Restore keeps provider")
        restored.draft = "问题🪞";restored.send()
        while restored.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        check(restored.error == nil && restored.messages.count == 4, "Multi-turn history replay")
        var legacy = record;legacy.agentProfile = nil
        check(CodexChatModel(reference: reference, directory: directory, memory: memory, restored: legacy).agent.kind == .codex, "Legacy memory migration")
        let stopped = CodexChatModel(reference: reference, directory: directory, memory: memory)
        custom.executable = directory.appendingPathComponent("slow").path
        stopped.selectAgent(custom);stopped.draft = "问题🪞";stopped.send()
        try await Task.sleep(for: .milliseconds(100));stopped.stop()
        check(!stopped.isRunning && stopped.status == "已停止", "Cancellation")
        let count = memory.records.count
        restored.startNewConversation(with: .preset(.claude))
        check(restored.messages.isEmpty && restored.reference != nil && restored.agent.kind == .claude, "New conversation restores quote")
        check(memory.records.count == count, "Switch preserves old conversation")
        check(chat.deleteMemory(), "Single record deletion succeeds")
        check(chat.recordDeleted && !chat.remembered, "Deletion reaches the open conversation")
        memory.save(record)
        check(!memory.records.contains { $0.id == record.id }, "Late saves cannot resurrect deleted records")
        let deleting = CodexChatModel(reference: reference, directory: directory, memory: memory)
        deleting.selectAgent(custom); deleting.draft = "删除中的问题"; deleting.send()
        let deadline = Date().addingTimeInterval(3)
        while !deleting.remembered && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        check(deleting.remembered && deleting.isRunning, "Streaming record exists before deletion")
        deleting.dismissFromUI()
        let streamingID = memory.records.first { $0.messages.first?.displayText == "删除中的问题" }!.id
        let otherIDs = Set(memory.records.filter { $0.id != streamingID }.map(\.id))
        check(memory.delete(ids: [streamingID]), "Delete background record")
        check(deleting.recordDeleted && !deleting.isRunning, "Deleted background generation is stopped")
        check(Set(memory.records.map(\.id)) == otherIDs, "Single deletion preserves unrelated conversations")
        check(memory.delete(ids: otherIDs), "Batch deletion")
        check(CodexMemoryStore(url: directory.appendingPathComponent("memory.json"), defaults: defaults).records.isEmpty, "Deletion persists across reload")
        let failing = CodexMemoryStore(url: URL(fileURLWithPath: "/dev/null/memory.json"), defaults: defaults)
        check(!failing.delete(ids: [record.id]) && !failing.isDeleted(record.id), "Failed deletion rolls back its tombstone")
        let initialGeneration = failing.generation
        check(!failing.clear() && failing.generation == initialGeneration, "Failed clear preserves active generation")
        chat.shutdown();restored.shutdown();stopped.shutdown()
        print("PASS: CLI adapters, UTF-8, HTTP/SSE, redirect/error/truncation, persistence, provider isolation, multi-turn, cancellation")
        exit(0)
    } catch { print("FAIL: \(error)");exit(1) }
}
NSApplication.shared.run()

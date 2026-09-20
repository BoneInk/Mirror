import AppKit
import SwiftUI
import Darwin

/// A persisted conversation. Never creates a replacement thread or replays an uncertain send.
@MainActor
final class CodexExistingThreadModel: ObservableObject {
    struct Message: Identifiable {
        let id: String
        let role: String
        var text: String
    }
    let thread: CodexThreadSummary
    @Published var draft: String
    @Published private(set) var messages: [Message] = []
    @Published private(set) var busy = false
    @Published private(set) var running = false
    @Published private(set) var error: String?
    @Published private(set) var status = ""
    @Published private(set) var needsReload = true
    private let server = CodexAppServer()
    private let desktopRunning: () -> Bool
    private let injectedRequest: ((String, [String: Any]) async throws -> [String: Any])?
    private var lockFD: Int32 = -1
    private var uncertainSend = false
    private var resumed = false
    private var disposed = false
    private var turnID: String?
    private var generation = UUID()
    private var observer: NSObjectProtocol?

    init(thread: CodexThreadSummary, reference: DocumentReference,
         desktopRunning: @escaping () -> Bool = {
             NSWorkspace.shared.runningApplications.contains {
                 $0.bundleIdentifier?.hasPrefix("com.openai.codex") == true
             }
         }, request: ((String, [String: Any]) async throws -> [String: Any])? = nil) {
        self.thread = thread
        draft = reference.markdown + "\n\n"
        self.desktopRunning = desktopRunning
        injectedRequest = request
        server.onNotification = { [weak self] method, params in self?.receive(method, params) }
        server.onDisconnect = { [weak self] _ in
            self?.invalidate("连接中断。发送结果可能已保存，请刷新历史核对后再发送，避免重复。")
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.desktopRunning(), self.resumed || self.running else { return }
                    self.invalidate("Codex 桌面已启动，Mirror 已断开。请退出 Codex 后刷新历史再继续。")
                }
            }
    }

    private func request(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
        if let injectedRequest { return try await injectedRequest(method, params) }
        try await server.connect()
        return try await server.request(method, params)
    }

    private func requireExclusiveAccess() throws {
        guard !desktopRunning() else {
            throw CodexConnectionError(message: "请先退出 Codex 桌面应用（⌘Q，仅关闭窗口不够），再在 Mirror 发送。也请停止其他客户端中的同一会话。")
        }
    }

    func load() async {
        guard !disposed, !busy, !running else { return }
        busy = true; error = nil
        let token = generation
        defer { if token == generation { busy = false } }
        do {
            let result = try await request("thread/read", ["threadId": thread.id, "includeTurns": true])
            guard token == generation else { return }
            try applyHistory(result)
            needsReload = false
            if uncertainSend { error = "上次发送结果未确认。请核对上方历史，删除已发送的草稿内容后再继续。" }
            status = desktopRunning() ? "历史已加载；退出 Codex 后即可发送。" : "历史已加载，可以继续原会话。"
        } catch {
            guard token == generation else { return }
            self.error = error.localizedDescription
            needsReload = true
        }
    }

    private func applyHistory(_ result: [String: Any]) throws {
        guard let value = result["thread"] as? [String: Any], value["id"] as? String == thread.id,
              let turns = value["turns"] as? [[String: Any]] else {
            throw CodexConnectionError(message: "无法读取原会话历史，请更新 Codex 后重试。")
        }
        messages = turns.flatMap { turn in
            (turn["items"] as? [[String: Any]] ?? []).compactMap(Self.message)
        }
    }

    private static func message(_ item: [String: Any]) -> Message? {
        guard let id = item["id"] as? String, let type = item["type"] as? String else { return nil }
        switch type {
        case "userMessage":
            let content = item["content"] as? [[String: Any]] ?? []
            let text = content.map { $0["text"] as? String ?? "[非文本附件]" }.joined(separator: "\n")
            return Message(id: id, role: "你", text: text)
        case "agentMessage": return Message(id: id, role: "Codex", text: item["text"] as? String ?? "")
        case "commandExecution", "fileChange", "mcpToolCall", "dynamicToolCall", "webSearch":
            return Message(id: id, role: "工具", text: "\(type) · \(item["status"] as? String ?? "")")
        default: return nil
        }
    }

    func send() async {
        guard !disposed, !busy, !running, !needsReload,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        busy = true; error = nil
        let token = generation
        var submitted = false
        defer { if token == generation { busy = false } }
        do {
            try requireExclusiveAccess()
            if !resumed {
                try acquireLock()
                let result = try await request("thread/resume", ["threadId": thread.id,
                    "approvalPolicy": "never", "sandbox": "read-only"])
                guard token == generation else { return }
                try applyHistory(result)
                resumed = true
            }
            try requireExclusiveAccess()
            let text = draft
            running = true; turnID = nil
            status = "正在生成…"
            submitted = true
            let result = try await request("turn/start", ["threadId": thread.id,
                "input": [["type": "text", "text": text]], "approvalPolicy": "never",
                "sandboxPolicy": ["type": "readOnly"]])
            guard token == generation else { return }
            if running { turnID = (result["turn"] as? [String: Any])?["id"] as? String }
            draft = ""
            uncertainSend = false
        } catch {
            guard token == generation else { return }
            if submitted {
                uncertainSend = true
                invalidate("发送结果尚未确认，草稿已保留。请刷新历史核对，避免重复发送。\n" + error.localizedDescription)
            } else if resumed || lockFD >= 0 {
                invalidate(error.localizedDescription)
            } else {
                self.error = error.localizedDescription
                running = false
            }
        }
    }

    func receive(_ method: String, _ params: [String: Any]) {
        guard !disposed else { return }
        if method == "mirror/actionUnavailable" {
            status = "此操作需要桌面工具或交互批准，Mirror 暂不支持。"
            return
        }
        guard params["threadId"] as? String == thread.id else { return }
        if let eventTurn = params["turnId"] as? String, let turnID, eventTurn != turnID { return }
        switch method {
        case "turn/started":
            guard running else { return }
            turnID = (params["turn"] as? [String: Any])?["id"] as? String
        case "item/started", "item/completed":
            guard running, let item = params["item"] as? [String: Any], let message = Self.message(item) else { return }
            if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
            else { messages.append(message) }
        case "item/agentMessage/delta":
            guard running, let id = params["itemId"] as? String, let delta = params["delta"] as? String else { return }
            if let index = messages.firstIndex(where: { $0.id == id }) { messages[index].text += delta }
            else { messages.append(Message(id: id, role: "Codex", text: delta)) }
        case "turn/completed":
            guard running, let turn = params["turn"] as? [String: Any],
                  turnID == nil || turn["id"] as? String == turnID else { return }
            running = false; turnID = nil
            status = turn["status"] as? String == "interrupted" ? "已停止" : "本轮已结束，历史保存在原会话中。"
            if let failure = turn["error"] as? [String: Any] { error = failure["message"] as? String }
        case "error":
            if params["willRetry"] as? Bool != true {
                invalidate((params["error"] as? [String: Any])?["message"] as? String ?? "会话发生错误，请刷新历史。")
            }
        default: break
        }
    }

    func stop() async {
        guard running else { return }
        guard let turnID else { invalidate("已断开连接。请刷新历史确认生成状态。"); return }
        do { _ = try await request("turn/interrupt", ["threadId": thread.id, "turnId": turnID]) }
        catch { invalidate("停止结果未确认，请刷新历史。" + error.localizedDescription) }
    }

    private func acquireLock() throws {
        guard lockFD < 0, injectedRequest == nil else { return }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Mirror/ThreadLocks")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = Darwin.open(directory.appendingPathComponent(thread.id + ".lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CodexConnectionError(message: "无法建立会话锁，请检查 Mirror 数据目录权限。") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw CodexConnectionError(message: "另一个 Mirror 窗口或进程正在使用此会话，请先关闭它。")
        }
        lockFD = fd
    }

    private func invalidate(_ message: String) {
        if running { uncertainSend = true }
        generation = UUID()
        server.close(); resumed = false; running = false; busy = false; turnID = nil
        if lockFD >= 0 { flock(lockFD, LOCK_UN); Darwin.close(lockFD); lockFD = -1 }
        needsReload = true; error = message
    }

    func close() {
        disposed = true
        invalidate("")
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}

@MainActor
final class CodexExistingThreadPanel: NSWindowController, NSWindowDelegate {
    private static var panels: [String: CodexExistingThreadPanel] = [:]
    let model: CodexExistingThreadModel

    static func open(thread: CodexThreadSummary, reference: DocumentReference) {
        if let existing = panels[thread.id] {
            existing.model.draft += "\n\n" + reference.markdown
            existing.showWindow(nil); existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let panel = CodexExistingThreadPanel(thread: thread, reference: reference)
        panels[thread.id] = panel
        panel.showWindow(nil); panel.window?.makeKeyAndOrderFront(nil)
    }

    init(thread: CodexThreadSummary, reference: DocumentReference) {
        model = CodexExistingThreadModel(thread: thread, reference: reference)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Mirror · " + thread.title
        window.minSize = NSSize(width: 560, height: 500)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: CodexExistingThreadView(model: model))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.running || model.busy {
            sender.orderOut(nil) // Retain the connection and output until the user reopens this conversation.
            return false
        }
        if !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let alert = NSAlert()
            alert.messageText = "关闭并丢弃未发送的草稿？"
            alert.addButton(withTitle: "保留草稿")
            alert.addButton(withTitle: "丢弃并关闭")
            return alert.runModal() == .alertSecondButtonReturn
        }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        model.close(); Self.panels.removeValue(forKey: model.thread.id)
    }
}

struct CodexExistingThreadView: View {
    @ObservedObject var model: CodexExistingThreadModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.thread.title).font(.headline).lineLimit(2)
            Text("退出 Codex 后在此续聊，消息保存在原会话。支持文字与只读工具；桌面专属工具和交互批准暂不支持。生成时关闭窗口会在后台继续。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(model.messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role).font(.caption.bold()).foregroundStyle(.secondary)
                                Text(message.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }.id(message.id)
                        }
                    }.padding(8)
                }.onChange(of: model.messages.last?.text) { _, _ in
                    if model.running, let id = model.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            if let error = model.error, !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text(model.status).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $model.draft).font(.body).frame(height: 120)
                .border(Color.secondary.opacity(0.3)).disabled(model.busy || model.running)
                .accessibilityLabel("续聊内容与文档引用")
            HStack {
                Button("刷新历史") { Task { await model.load() } }.disabled(model.busy || model.running)
                Spacer()
                if model.running { Button("停止生成") { Task { await model.stop() } } }
                Button(model.busy ? "正在连接…" : "发送") { Task { await model.send() } }
                    .keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.running || model.needsReload || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).task { await model.load() }
    }
}

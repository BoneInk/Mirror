import AppKit
import SwiftUI

/// Metadata only. Listing never resumes or modifies a user's Codex thread.
struct CodexThreadSummary: Identifiable, Equatable {
    let id: String
    let title: String
    let preview: String
    let directory: String
    let updatedAt: Date?

    init(json: [String: Any]) throws {
        guard let id = json["id"] as? String, UUID(uuidString: id) != nil else {
            throw CodexConnectionError(message: "Codex 返回了无效的会话编号，请更新 Codex 后重试。")
        }
        self.id = id
        preview = json["preview"] as? String ?? ""
        let name = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        title = name.flatMap { $0.isEmpty ? nil : $0 } ?? (preview.isEmpty ? "未命名会话" : String(preview.prefix(120)))
        directory = json["cwd"] as? String ?? ""
        updatedAt = (json["updatedAt"] as? Double).map(Date.init(timeIntervalSince1970:))
    }
}

@MainActor
final class CodexThreadPickerModel: ObservableObject {
    @Published private(set) var threads: [CodexThreadSummary] = []
    @Published var selectedID: String?
    @Published private(set) var loading = false
    @Published private(set) var handingOff = false
    @Published private(set) var error: String?
    @Published private(set) var feedback: String?
    @Published private(set) var nextCursor: String?
    @Published var search = "" {
        didSet {
            if let selectedID, !visibleThreads.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
        }
    }
    let reference: DocumentReference
    private let server: CodexAppServer
    private let executable: URL?
    private let request: (String, [String: Any]) async throws -> [String: Any]
    private let openURL: (URL) -> Bool
    private let desktopAvailable: () -> Bool
    private let usesInjectedRequest: Bool
    private var disposed = false
    private var connected = false
    private var generation = UUID()

    init(reference: DocumentReference, executable: URL? = nil,
         request: ((String, [String: Any]) async throws -> [String: Any])? = nil,
         openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
         desktopAvailable: @escaping () -> Bool = {
             NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") != nil
         }) {
        self.reference = reference
        self.executable = executable
        let server = CodexAppServer()
        self.server = server
        self.request = request ?? { method, params in try await server.request(method, params) }
        self.openURL = openURL
        self.desktopAvailable = desktopAvailable
        usesInjectedRequest = request != nil
        connected = request != nil
        server.onDisconnect = { [weak self] _ in self?.connected = false }
    }

    var selected: CodexThreadSummary? { threads.first { $0.id == selectedID } }
    var visibleThreads: [CodexThreadSummary] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? threads : threads.filter {
            [$0.title, $0.preview, $0.directory, $0.id].contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
    var canReference: Bool { selected != nil && !loading && !handingOff && feedback == nil }

    func load(more: Bool = false) async {
        guard !disposed, !Task.isCancelled, !loading, !handingOff, !more || nextCursor != nil else { return }
        let token = generation
        loading = true; error = nil
        defer { if generation == token { loading = false } }
        do {
            if !connected && !usesInjectedRequest {
                try await server.connect(executable: executable)
                connected = true
            }
            var params: [String: Any] = ["limit": 50, "sortKey": "updated_at", "archived": false,
                                         "sourceKinds": ["cli", "vscode", "appServer", "exec"]]
            if more, let nextCursor { params["cursor"] = nextCursor }
            let response = try await request("thread/list", params)
            try Task.checkCancellation()
            guard generation == token else { return }
            guard let data = response["data"] as? [[String: Any]] else {
                throw CodexConnectionError(message: "Codex 未返回会话列表，请更新 Codex 后重试。")
            }
            let page = try data.filter { $0["ephemeral"] as? Bool != true }.map(CodexThreadSummary.init)
            var seen = Set<String>()
            threads = ((more ? threads : []) + page).filter { seen.insert($0.id).inserted }
            nextCursor = response["nextCursor"] as? String
            if more, nextCursor == params["cursor"] as? String {
                nextCursor = nil
                throw CodexConnectionError(message: "Codex 返回了重复的分页游标，请刷新列表。")
            }
            if selected == nil { selectedID = nil }
        } catch {
            guard generation == token else { return }
            self.error = error.localizedDescription
            // A failed refresh must not leave a stale target enabled.
            if !more { threads = []; selectedID = nil; nextCursor = nil }
            connected = false
            server.close()
        }
    }

    func referenceSelection() async {
        guard !disposed, !Task.isCancelled, canReference, let target = selected else { return }
        let token = generation
        handingOff = true; error = nil
        defer { if generation == token { handingOff = false } }
        do {
            guard desktopAvailable() else {
                throw CodexConnectionError(message: "请安装并打开 Codex 桌面应用。仅安装 CLI 可以查看会话，但无法填入桌面草稿。")
            }
            if !connected && !usesInjectedRequest {
                try await server.connect(executable: executable)
                connected = true
            }
            // Revalidate the exact target before handing off. Never fall back to a new thread.
            let response = try await request("thread/read", ["threadId": target.id, "includeTurns": false])
            try Task.checkCancellation()
            guard generation == token else { return }
            guard let thread = response["thread"] as? [String: Any], thread["id"] as? String == target.id else {
                throw CodexConnectionError(message: "目标会话已不可用，请刷新列表并重新选择。")
            }
            guard let url = CodexReference.desktopURL(prompt: reference.markdown, threadID: target.id) else {
                throw CodexConnectionError(message: "无法生成引用链接，引用内容已保留。")
            }
            // Bound the OS URL handoff; never silently truncate a quotation.
            guard url.absoluteString.utf8.count <= 64 * 1024 else {
                throw CodexConnectionError(message: "引用内容过长，请缩小选区后重试（引用链接上限 64 KB）。")
            }
            guard openURL(url) else {
                throw CodexConnectionError(message: "无法打开 Codex，引用内容已保留。请确认桌面应用可运行后重试。")
            }
            feedback = "已请求打开「\(target.title)」并填入引用草稿。请在 Codex 中核对并发送。"
        } catch {
            guard generation == token else { return }
            self.error = error.localizedDescription
        }
    }

    func close() {
        disposed = true
        generation = UUID()
        server.close(); connected = false; loading = false; handingOff = false
    }
}

@MainActor
final class CodexThreadPickerPanel: NSWindowController, NSWindowDelegate {
    private static var panels: [UUID: CodexThreadPickerPanel] = [:]
    private let id = UUID()
    let model: CodexThreadPickerModel

    static func open(reference: DocumentReference) {
        let panel = CodexThreadPickerPanel(reference: reference)
        panels[panel.id] = panel
        panel.showWindow(nil)
        panel.window?.makeKeyAndOrderFront(nil)
    }

    init(reference: DocumentReference) {
        // Prefer the installed desktop runtime so list and URL handoff use the same local store.
        model = CodexThreadPickerModel(reference: reference)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 640),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "引用到 Codex 会话"
        window.minSize = NSSize(width: 540, height: 520)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: CodexThreadPickerView(model: model, close: { [weak self] in self?.close() }))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { model.close(); Self.panels.removeValue(forKey: id) }
}

struct CodexThreadPickerView: View {
    @ObservedObject var model: CodexThreadPickerModel
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择接收引用的 Codex 会话").font(.headline)
            Text("显示本机未归档会话。引用将填入目标会话草稿，在 Codex 中确认发送。")
                .font(.caption).foregroundStyle(.secondary)
            GroupBox("引用内容") {
                ScrollView { Text(model.reference.markdown).font(.system(size: 12)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 90)
            }
            HStack {
                TextField("搜索已加载的会话、内容或路径", text: $model.search).textFieldStyle(.roundedBorder)
                Button("刷新", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .disabled(model.loading || model.handingOff)
            }
            if model.loading && model.threads.isEmpty {
                Spacer(); HStack { Spacer(); ProgressView("正在读取 Codex 会话…"); Spacer() }; Spacer()
            } else if model.threads.isEmpty {
                ContentUnavailableView("暂无可用会话", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("请先在 Codex 中创建会话，再点击刷新。请确认 Mirror 与 Codex 使用相同的 CODEX_HOME。"))
            } else if model.visibleThreads.isEmpty {
                ContentUnavailableView.search(text: model.search)
            } else {
                List(selection: $model.selectedID) {
                    ForEach(model.visibleThreads) { thread in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(thread.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                            if !thread.preview.isEmpty { Text(thread.preview).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                            HStack {
                                Text(thread.directory.isEmpty ? thread.id : thread.directory).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                if let date = thread.updatedAt { Text(date, style: .date) }
                            }.font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(thread.id)
                    }
                }.disabled(model.handingOff).accessibilityLabel("Codex 会话列表")
            }
            if model.nextCursor != nil {
                Button(model.loading ? "正在加载…" : "加载更多会话") { Task { await model.load(more: true) } }
                    .disabled(model.loading || model.handingOff)
            }
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            if let feedback = model.feedback { Label(feedback, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green) }
            Text("将替换目标会话未发送的草稿；如有原草稿，请先在 Codex 中保存。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(model.selected.map { "目标：\($0.title)" } ?? "请选择一个目标会话").font(.caption).lineLimit(1)
                Spacer()
                Button("关闭", action: close).keyboardShortcut(.cancelAction)
                Button(model.handingOff ? "正在打开…" : "引用到此会话") { Task { await model.referenceSelection() } }
                    .buttonStyle(.borderedProminent).disabled(!model.canReference)
            }
        }.padding(20).frame(minWidth: 500, minHeight: 460)
            .task { await model.load() }
    }
}

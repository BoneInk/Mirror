import AppKit
import SwiftUI

/// UTF-16 anchors use surrounding text to distinguish repeated quotations.
struct CodexTextAnchor: Codable, Equatable {
    let quote: String
    let prefix: String
    let suffix: String
    let offset: Int
    var occurrenceCount: Int? = nil

    static func capture(in text: String, range: NSRange) -> CodexTextAnchor? {
        let text = text as NSString
        guard range.location != NSNotFound, range.length > 0, NSMaxRange(range) <= text.length else { return nil }
        let before = max(0, range.location - 48), after = min(text.length, NSMaxRange(range) + 48)
        let quote = text.substring(with: range)
        let count = (text as String).components(separatedBy: quote).count - 1
        return CodexTextAnchor(quote: quote,
            prefix: text.substring(with: NSRange(location: before, length: range.location - before)),
            suffix: text.substring(with: NSRange(location: NSMaxRange(range), length: after - NSMaxRange(range))), offset: range.location, occurrenceCount: count)
    }

    func resolve(in text: String) -> NSRange? {
        let text = text as NSString
        guard !quote.isEmpty else { return nil }
        var matches: [NSRange] = [], cursor = 0
        while cursor < text.length {
            let range = text.range(of: quote, options: .literal, range: NSRange(location: cursor, length: text.length - cursor))
            if range.location == NSNotFound { break }
            matches.append(range)
            cursor = NSMaxRange(range)
        }
        if matches.count == 1 && (occurrenceCount ?? 1) == 1 { return matches[0] }
        let contextual = matches.filter { range in
            let before = text.substring(to: range.location), after = text.substring(from: NSMaxRange(range))
            return (!prefix.isEmpty || !suffix.isEmpty) && before.hasSuffix(prefix) && after.hasPrefix(suffix)
        }
        // Never silently choose the first of two indistinguishable occurrences.
        return contextual.count == 1 ? contextual[0] : nil
    }
}

struct CodexMemoryRecord: Codable, Identifiable {
    let id: UUID
    let filePath: String
    let title: String
    let quote: String
    let location: String?
    let sourceAnchor: CodexTextAnchor?
    let renderedAnchor: CodexTextAnchor?
    var threadID: String?
    var messages: [CodexChatMessage]
    var updatedAt: Date
    var agentProfile: AgentProfile? = nil
    var menuTitle: String { (agentProfile?.name ?? "Codex") + " · " + String((messages.first?.displayText ?? quote).prefix(60)) }
}

@MainActor
final class CodexMemoryStore: ObservableObject {
    static let shared = CodexMemoryStore()
    static let changed = Notification.Name("MirrorCodexMemoryChanged")
    private let defaults: UserDefaults
    private let url: URL
    private var unreadable = false
    private var deletedIDs = Set<UUID>()
    private(set) var generation = 0
    @Published private(set) var records: [CodexMemoryRecord] = []
    @Published private(set) var error: String?
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "codexBubbleMemoryEnabled")
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
    }

    init(url: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mirror/CodexConversations.json")
        enabled = defaults.object(forKey: "codexBubbleMemoryEnabled") as? Bool ?? true
        if FileManager.default.fileExists(atPath: self.url.path) {
            do { records = try JSONDecoder().decode([CodexMemoryRecord].self, from: Data(contentsOf: self.url)) }
            catch { unreadable = true; self.error = "无法读取气泡记忆：\(error.localizedDescription)" }
        }
    }

    func records(for url: URL?) -> [CodexMemoryRecord] {
        guard enabled, let url else { return [] }
        return records.filter { $0.filePath == url.standardizedFileURL.path }
    }

    func save(_ record: CodexMemoryRecord) {
        guard enabled, !unreadable, !deletedIDs.contains(record.id) else { return }
        var next = records
        if let index = next.firstIndex(where: { $0.id == record.id }) { next[index] = record }
        else { next.append(record) }
        write(next)
    }

    func isDeleted(_ id: UUID) -> Bool { deletedIDs.contains(id) }

    @discardableResult
    func delete(ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty, !unreadable else { return false }
        let previous = deletedIDs
        deletedIDs.formUnion(ids)
        if write(records.filter { !ids.contains($0.id) }) { return true }
        deletedIDs = previous
        return false
    }

    @discardableResult
    func clear() -> Bool {
        generation += 1
        if write([]) { return true }
        generation -= 1
        return false
    }

    @discardableResult
    private func write(_ next: [CodexMemoryRecord]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            records = next
            unreadable = false
            error = nil
            NotificationCenter.default.post(name: Self.changed, object: self)
            return true
        } catch { self.error = "无法保存气泡记忆：\(error.localizedDescription)"; return false }
    }
}

struct CodexMemorySettingsView: View {
    @ObservedObject private var memory = CodexMemoryStore.shared
    @State private var confirmingClear = false
    @State private var editing = false
    @State private var selected = Set<UUID>()
    @State private var pendingDeletion = Set<UUID>()
    @State private var confirmingDeletion = false
    @State private var search = ""
    init(editing: Bool = false) { self._editing = State(initialValue: editing) }
    private var visibleRecords: [CodexMemoryRecord] {
        memory.records.filter { record in
            search.isEmpty || [record.menuTitle, record.filePath, record.quote].contains { $0.localizedCaseInsensitiveContains(search) }
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("记住引用位置和对话", isOn: $memory.enabled)
            Text("在原文位置显示对话标记。关闭后保留已有记录；未保存的文档需先保存，才能保留位置记忆。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("搜索问题、文档或智能体", text: $search).textFieldStyle(.roundedBorder)
                Button(editing ? "完成" : "批量编辑") { editing.toggle(); selected.removeAll() }
                    .disabled(memory.records.isEmpty)
            }
            if editing {
                HStack {
                    Button("全选当前结果") { selected.formUnion(visibleRecords.map(\.id)) }
                    Button("取消选择") { selected.removeAll() }.disabled(selected.isEmpty)
                    Spacer()
                    Button("删除所选（\(selected.count)）", role: .destructive) {
                        pendingDeletion = selected; confirmingDeletion = true
                    }.disabled(selected.isEmpty)
                }.controlSize(.small)
            }
            List {
                ForEach(visibleRecords) { record in
                    HStack(alignment: .top, spacing: 10) {
                        if editing {
                            Toggle("选择记录", isOn: Binding(get: { selected.contains(record.id) }, set: { value in
                                if value { selected.insert(record.id) } else { selected.remove(record.id) }
                            })).labelsHidden().toggleStyle(.checkbox)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.menuTitle).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text(URL(fileURLWithPath: record.filePath).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                                .help(record.filePath)
                            Text(record.updatedAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if !editing {
                            Button(role: .destructive) {
                                pendingDeletion = [record.id]; confirmingDeletion = true
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).help("删除这条记录")
                        }
                    }.padding(.vertical, 4)
                }
                if visibleRecords.isEmpty { Text(search.isEmpty ? "还没有保存的对话" : "没有匹配的记录").foregroundStyle(.secondary) }
            }.listStyle(.inset)
            HStack {
                Text("共 \(memory.records.count) 条 · 仅删除本机记录和标记，不删除智能体服务中的会话。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("全部清除…", role: .destructive) { confirmingClear = true }
                    .disabled(memory.records.isEmpty && memory.error == nil)
            }
            if let error = memory.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .onChange(of: memory.records.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .confirmationDialog("删除所选的 \(pendingDeletion.count) 条本机记录？", isPresented: $confirmingDeletion) {
            Button("删除", role: .destructive) {
                if memory.delete(ids: pendingDeletion) { selected.subtract(pendingDeletion); pendingDeletion.removeAll() }
            }
        }
        .confirmationDialog("清除所有本机气泡记忆？", isPresented: $confirmingClear) {
            Button("清除", role: .destructive) { memory.clear() }
        }
    }
}

import AppKit
import SwiftUI
import Security

// Configuration snapshots belong to a conversation; credentials stay in Keychain.
enum AgentKind: String, Codable, CaseIterable, Identifiable {
    case codex, claude, codebuddy, cursor, hermes, kimi, qoder, workbuddy, qwenwork, deepseekHarness, openclaw, opencode, pi, smartwork, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .codebuddy: return "CodeBuddy"
        case .cursor: return "Cursor"
        case .hermes: return "Hermes"
        case .kimi: return "Kimi"
        case .qoder: return "Qoder"
        case .workbuddy: return "WorkBuddy"
        case .qwenwork: return "千问办公"
        case .deepseekHarness: return "DeepSeek Harness"
        case .openclaw: return "OpenClaw"
        case .opencode: return "OpenCode"
        case .pi: return "Pi Agent"
        case .smartwork: return "Smartwork"
        case .custom: return "自定义智能体"
        }
    }
    var supportsNative: Bool { [.codex, .claude, .codebuddy, .cursor, .kimi, .qoder, .opencode, .pi].contains(self) }
    var command: String {
        switch self {
        case .claude: return "claude"
        case .cursor: return "cursor-agent"
        case .opencode: return "opencode"
        case .pi: return "pi"
        case .deepseekHarness: return "deepseek-harness"
        case .smartwork: return "smartwork"
        default: return rawValue
        }
    }
}
enum AgentConnection: String, Codable, CaseIterable, Identifiable {
    case native, chatCompletions, smartwork, workbuddy, command
    var id: String { rawValue }
    var title: String {
        switch self {
        case .native: return "原生命令行"
        case .workbuddy: return "WorkBuddy 本地助理 Open API"
        case .smartwork: return "D-Chat / Smartwork 本地 Agent"
        case .chatCompletions: return "OpenAI 兼容 HTTP"
        case .command: return "自定义命令（stdin → stdout）"
        }
    }
}
struct AgentProfile: Codable, Identifiable, Equatable {
    var id: String
    var kind: AgentKind
    var name: String
    var connection: AgentConnection
    var executable = ""
    var arguments = "[]"
    var endpoint = ""
    var model = ""
    static func preset(_ kind: AgentKind) -> Self {
        var result = Self(id: kind.rawValue, kind: kind, name: kind.title,
                          connection: kind.supportsNative ? .native : .chatCompletions)
        switch kind {
        case .smartwork: result.connection = .smartwork; result.endpoint = "http://127.0.0.1:8764"
        case .openclaw: result.endpoint = "http://127.0.0.1:18789/v1"; result.model = "openclaw/default"
        case .hermes: result.endpoint = "http://127.0.0.1:8642/v1"; result.model = "hermes-agent"
        case .workbuddy: result.connection = .workbuddy; result.endpoint = "https://www.workbuddy.cn/openapi/v2"
        case .qwenwork: result.connection = .command
        default: break
        }
        return result
    }

    var validation: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请输入配置名称。" }
        if connection == .chatCompletions || connection == .smartwork || connection == .workbuddy {
            guard let url = URL(string: endpoint), let host = url.host, !host.isEmpty,
                  ["http", "https"].contains(url.scheme ?? ""), url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { return "请输入有效的 HTTP / HTTPS 基础地址，不要在地址中放入密钥。" }
            if model.isEmpty && connection == .chatCompletions { return "请填写模型或智能体标识。" }
        } else if connection == .command {
            if executable.isEmpty { return "请选择可执行文件或包装脚本。" }
            guard let data = arguments.data(using: .utf8), (try? JSONDecoder().decode([String].self, from: data)) != nil else {
                return "命令参数应为 JSON 字符串数组，例如 [\"--print\"]。"
            }
        }
        return nil
    }
}
enum AgentCredential {
    static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "Mirror.Agent", kSecAttrAccount as String: id]
    }
    static func read(_ id: String) -> String {
        var q = query(id); q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String, id: String) throws {
        let q = query(id)
        if token.isEmpty { let status = SecItemDelete(q as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }; return }
        let attributes = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(q as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(q.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw failure(status) }
    }
    private static func failure(_ status: OSStatus) -> Error {
        CodexConnectionError(message: "无法保存认证信息到钥匙串（\(status)）。")
    }
}

@MainActor
final class AgentConfigurationStore: ObservableObject {
    static let shared = AgentConfigurationStore()
    @Published private(set) var profiles: [AgentProfile]
    @Published var selectedID: String { didSet { defaults.set(selectedID, forKey: "mirrorDefaultAgent") } }
    @Published private(set) var discoveries: [String: String] = [:]
    @Published private(set) var scanning = false
    @Published private(set) var localServices: [String] = []
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = defaults.data(forKey: "mirrorAgentProfiles").flatMap { try? JSONDecoder().decode([AgentProfile].self, from: $0) }
            ?? AgentKind.allCases.filter { $0 != .custom }.map(AgentProfile.preset)
        selectedID = defaults.string(forKey: "mirrorDefaultAgent") ?? "codex"
        // Upgrade only the untouched placeholder from v1.0; preserve user-configured endpoints.
        if let i = profiles.firstIndex(where: { $0.id == "smartwork" && $0.kind == .smartwork && $0.connection == .chatCompletions && $0.endpoint.isEmpty && $0.executable.isEmpty && $0.model.isEmpty }) {
            profiles[i] = .preset(.smartwork)
        }
        // Seed newly introduced presets once, without restoring configurations users later remove.
        if !defaults.bool(forKey: "mirrorAgentPresetsV11") {
            for kind in [AgentKind.codebuddy, .cursor, .hermes, .kimi, .qoder, .workbuddy, .qwenwork] where !profiles.contains(where: { $0.kind == kind }) {
                profiles.append(.preset(kind))
            }
            defaults.set(true, forKey: "mirrorAgentPresetsV11")
            persist()
        }
    }
    var selected: AgentProfile { profiles.first { $0.id == selectedID } ?? .preset(.codex) }
    func save(_ profile: AgentProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        persist()
    }
    func delete(_ profile: AgentProfile) {
        profiles.removeAll { $0.id == profile.id }
        if selectedID == profile.id { selectedID = "codex" }
        persist()
    }
    private func persist() { defaults.set(try? JSONEncoder().encode(profiles), forKey: "mirrorAgentProfiles") }
    static var executableDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":")
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.npm-global/bin", "\(home)/.opencode/bin", "\(home)/.codebuddy/bin", "\(home)/.qoder/bin"]
        let nvm = "\(home)/.nvm/versions/node"
        dirs += ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []).sorted().reversed().map { "\(nvm)/\($0)/bin" }
        return dirs.filter { !$0.isEmpty }
    }
    static func executable(for profile: AgentProfile) -> URL? {
        if !profile.executable.isEmpty {
            let path = (profile.executable as NSString).expandingTildeInPath
            if path.contains("/") { return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil }
            return executableDirectories.map { URL(fileURLWithPath: $0).appendingPathComponent(path) }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        }
        if profile.kind == .codex { return CodexAppServer.executableURL() }
        let names: [String]
        switch profile.kind {
        case .codebuddy: names = ["codebuddy", "cbc"] // buddycn opens the IDE; it is not the agent CLI.
        case .cursor: names = ["cursor-agent", "agent"]
        case .qoder: names = ["qoder", "qodercli"]
        default: names = [profile.kind.command]
        }
        return names.flatMap { name in executableDirectories.map { URL(fileURLWithPath: $0).appendingPathComponent(name) } }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static func isSmartworkHealth(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["ok"] as? Bool == true && object["name"] as? String == "smartwork-agent-runtime"
            && object["protocol"] as? String == "smartwork-agent-turns-v1"
    }

    func scan() async {
        guard !scanning else { return }; scanning = true; defer { scanning = false }
        var found: [String: String] = [:]
        for profile in profiles {
            if profile.connection == .workbuddy {
                found[profile.id] = "需配置开放平台 Access Token，并保持 WorkBuddy 电脑端在线"
                continue
            }
            if profile.kind == .qwenwork && profile.executable.isEmpty && profile.endpoint.isEmpty {
                found[profile.id] = "待配置办公 Agent 桥接；不使用普通千问模型接口"
                continue
            }
            if profile.connection == .smartwork {
                found[profile.id] = "未连接到 D-Chat / Smartwork Agent，请启动客户端或检查地址"
                if let base = URL(string: profile.endpoint), ["localhost", "127.0.0.1", "::1"].contains(base.host ?? "") {
                    var request = URLRequest(url: base.appendingPathComponent("api/agent/health")); request.timeoutInterval = 1.5
                    let client = URLSession(configuration: .ephemeral, delegate: AgentNoRedirect(), delegateQueue: nil)
                    defer { client.invalidateAndCancel() }
                    if let (data, response) = try? await client.data(for: request), let http = response as? HTTPURLResponse {
                        if http.statusCode == 200 && Self.isSmartworkHealth(data) {
                            found[profile.id] = "Smartwork Agent 已就绪 · " + profile.endpoint
                        } else if http.statusCode == 401 || http.statusCode == 403 {
                            found[profile.id] = "本地服务需要认证，请配置 Smartwork Token"
                        } else { found[profile.id] = "端口有响应，但未确认 Smartwork Agent 协议" }
                    }
                }
                continue
            }
            if let executable = Self.executable(for: profile) { found[profile.id] = "检测到命令：\(executable.path)" }
            else { found[profile.id] = "未检测到命令，可手动配置" }
            if profile.connection == .chatCompletions, let base = URL(string: profile.endpoint),
               ["localhost", "127.0.0.1", "::1"].contains(base.host ?? "") {
                var request = URLRequest(url: base.appendingPathComponent("models")); request.timeoutInterval = 1.5
                // Discovery is unauthenticated and never sends prompts or reads credentials.
                let client = URLSession(configuration: .ephemeral, delegate: AgentNoRedirect(), delegateQueue: nil)
                defer { client.invalidateAndCancel() }
                if let (_, response) = try? await client.data(for: request), let http = response as? HTTPURLResponse {
                    found[profile.id] = "本地端口有响应（HTTP \(http.statusCode)），需确认协议与认证"
                }
            }
        }
        localServices = await Task.detached(priority: .utility) {
            let child = Process(), output = Pipe()
            child.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            child.arguments = ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "cn"]
            child.standardOutput = output; child.standardError = FileHandle.nullDevice
            guard (try? child.run()) != nil else { return [String]() }
            let data = output.fileHandleForReading.readDataToEndOfFile(); child.waitUntilExit()
            var command = "", services = Set<String>()
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if line.hasPrefix("c") { command = String(line.dropFirst()) }
                if line.hasPrefix("n"), let port = line.split(separator: ":").last, Int(port) != nil {
                    services.insert("\(command) · \(line.dropFirst())")
                }
            }
            return services.sorted()
        }.value
        discoveries = found
    }
}

struct AgentSettingsView: View {
    @ObservedObject private var store = AgentConfigurationStore.shared
    @State private var editing: AgentProfile?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("智能体").font(.title2.bold())
                Spacer()
                Button(store.scanning ? "检测中…" : "检测本机") { Task { await store.scan() } }.disabled(store.scanning)
                Menu("添加") {
                    ForEach(AgentKind.allCases) { kind in
                        Button(kind.title) { var profile = AgentProfile.preset(kind); profile.id = UUID().uuidString; editing = profile }
                    }
                }
            }
            Text("选择引用提问的默认智能体。已有对话继续使用创建时的配置。").font(.callout).foregroundStyle(.secondary)
            Picker("默认智能体", selection: $store.selectedID) {
                ForEach(store.profiles) { profile in Text(profile.name).tag(profile.id) }
            }
            if !store.localServices.isEmpty {
                DisclosureGroup("本机监听端口（\(store.localServices.count)，协议待确认）") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(store.localServices, id: \.self) { service in Text(service).font(.caption.monospaced()).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 90)
                }
            }
            List(store.profiles) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name).font(.headline)
                        Text(store.discoveries[profile.id] ?? profile.connection.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("配置…") { editing = profile }.buttonStyle(.borderless)
                    if profile.id != "codex" { Button { store.delete(profile) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).foregroundStyle(.secondary).help("移除配置（保留历史对话）") }
                }.padding(.vertical, 4)
            }.listStyle(.inset)
        }
        .task { await store.scan() }
        .sheet(item: $editing) { profile in AgentProfileEditor(profile: profile) { store.save($0); editing = nil } }
    }
}
struct AgentProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: AgentProfile
    @State private var token = ""
    @State private var clearToken = false
    @State private var error: String?
    let save: (AgentProfile) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("配置 \(profile.kind.title)").font(.title2.bold())
            VStack(alignment: .leading, spacing: 12) {
                field("名称", text: $profile.name)
                if profile.kind == .qwenwork {
                    Text("千问办公尚未确认公开的问答接口。请配置能调用办公 Agent 的包装命令或兼容服务；此预设不会直接调用普通千问模型。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if profile.kind == .hermes {
                    Text("连接 Hermes Agent 的 API Server。请先启用 API_SERVER_ENABLED，配置 API_SERVER_KEY，再启动 hermes gateway。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if profile.kind != .codex {
                    Picker("连接方式", selection: $profile.connection) {
                        if profile.kind.supportsNative { Text(AgentConnection.native.title).tag(AgentConnection.native) }
                        if profile.kind == .workbuddy { Text(AgentConnection.workbuddy.title).tag(AgentConnection.workbuddy) }
                        if profile.kind == .smartwork { Text(AgentConnection.smartwork.title).tag(AgentConnection.smartwork) }
                        Text(AgentConnection.chatCompletions.title).tag(AgentConnection.chatCompletions)
                        Text(AgentConnection.command.title).tag(AgentConnection.command)
                    }
                }
                if profile.connection == .chatCompletions || profile.connection == .smartwork || profile.connection == .workbuddy {
                    field(profile.connection == .smartwork ? "Agent 地址（默认 http://127.0.0.1:8764）" : profile.connection == .workbuddy ? "开放平台地址（包含 /openapi/v2）" : "基础地址（包含 /v1）", text: $profile.endpoint)
                    if profile.connection != .workbuddy {
                        field(profile.connection == .smartwork ? "模型（留空使用客户端默认值，或 provider::model）" : "模型 / 智能体", text: $profile.model)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("认证密钥").font(.caption).foregroundStyle(.secondary)
                        SecureField("API Key / Bearer Token", text: $token)
                            .onChange(of: token) { _, value in if !value.isEmpty { clearToken = false } }
                        HStack {
                            Text(clearToken ? "保存时清除密钥" : "留空保持原值；密钥保存在本机钥匙串。")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("清除密钥") { token = ""; clearToken = true }.buttonStyle(.borderless)
                        }
                    }
                    Text(profile.connection == .workbuddy ? "使用 WorkBuddy 开放平台授权后的 Access Token（localassistant.readable / invokable）。消息发送到本地助理，工具审批在 WorkBuddy 中处理。停止只停止等待；请避免同时在其他入口提问。" : profile.connection == .smartwork ? "直接连接 D-Chat / Smartwork 的本地 Agent 服务，复用客户端登录和模型配置；工具权限由 Smartwork 客户端管理。" : (profile.kind == .openclaw ? "需启用 Gateway 的 chatCompletions 接口；服务端工具权限由 Gateway 配置决定。" : "服务需兼容 /chat/completions 和 SSE。专有协议可切换为自定义命令包装。"))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    field("命令路径（留空自动检测）", text: $profile.executable)
                    if profile.connection == .command {
                        field("参数（JSON 字符串数组）", text: $profile.arguments)
                        Text("包装命令从 stdin 读取包含对话历史的文本，将回答写入 stdout，诊断写入 stderr。每轮启动一次；工具权限由该命令管理。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        field("模型（留空使用 CLI 默认值）", text: $profile.model)
                        Text("复用本机 CLI 登录。Mirror 使用阅读问答模式；请先在终端完成 CLI 安装和登录。")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    if let problem = profile.validation { error = problem; return }
                    do {
                        if clearToken || !token.isEmpty { try AgentCredential.save(token, id: profile.id) }
                        save(profile)
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560)
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text).labelsHidden().frame(maxWidth: .infinity)
        }
    }

}

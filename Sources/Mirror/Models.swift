import SwiftUI

struct Heading: Identifiable, Equatable, Sendable {
    let id = UUID()
    let level: Int
    let title: String
    let line: Int
}

struct WorkspaceNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let children: [WorkspaceNode]?

    var id: String { url.path }
}

struct WorkspaceSnapshot {
    let files: [URL]
    let tree: [WorkspaceNode]
    let markdownTree: [WorkspaceNode]
    let markdownCount: Int
}

struct OpenDocumentTab: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var text: String
    var filePath: String?
    var previewPath: String?
    var encodingRawValue: UInt
    var lineEndingRawValue: String?
    var fileRevision: FileRevision?
    var isDirty: Bool
    var selectionLocation: Int
    var selectionLength: Int
    var readerMode: Bool

    var title: String {
        let path = previewPath ?? filePath
        return path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? "Untitled"
    }

    var isPreview: Bool { previewPath != nil }
}

struct FileRevision: Codable, Equatable, Sendable {
    let modificationTime: TimeInterval
    let fileSize: Int
    let contentFingerprint: UInt64?
}

struct ExternalFileConflict: Identifiable, Equatable, Sendable {
    let id = UUID()
    let url: URL
    let detectedAt: Date
}

struct WorkspaceSearchResult: Identifiable, Equatable, Sendable {
    let url: URL
    let line: Int
    let column: Int
    let preview: String
    let matchLength: Int

    var id: String { "\(url.path):\(line):\(column)" }
}

struct DocumentHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let originalPath: String
    let createdAt: Date
    let text: String
    let encodingRawValue: UInt
    let lineEndingRawValue: String

    var byteCount: Int { text.lengthOfBytes(using: .utf8) }
}

enum MarkdownTableAlignment: String, CaseIterable, Identifiable, Sendable {
    case leading = "Left"
    case center = "Center"
    case trailing = "Right"

    var id: String { rawValue }
    var marker: String {
        switch self {
        case .leading: return "---"
        case .center: return ":---:"
        case .trailing: return "---:"
        }
    }
}

enum DocumentLineEnding: String, Codable, CaseIterable, Identifiable, Sendable {
    case lf = "LF"
    case crlf = "CRLF"
    case cr = "CR"

    var id: String { rawValue }
}

struct TextEncodingChoice: Identifiable, Sendable {
    let name: String
    let rawValue: UInt
    var id: UInt { rawValue }

    static let common: [TextEncodingChoice] = [
        TextEncodingChoice(name: "UTF-8", rawValue: String.Encoding.utf8.rawValue),
        TextEncodingChoice(name: "UTF-16", rawValue: String.Encoding.utf16.rawValue),
        TextEncodingChoice(name: "UTF-16 Little Endian", rawValue: String.Encoding.utf16LittleEndian.rawValue),
        TextEncodingChoice(name: "UTF-16 Big Endian", rawValue: String.Encoding.utf16BigEndian.rawValue),
        TextEncodingChoice(name: "Windows-1252", rawValue: String.Encoding.windowsCP1252.rawValue),
        TextEncodingChoice(name: "ISO Latin-1", rawValue: String.Encoding.isoLatin1.rawValue),
        TextEncodingChoice(name: "Mac Roman", rawValue: String.Encoding.macOSRoman.rawValue)
    ]
}

enum EditableDocumentFormat: Equatable {
    case markdown
    case text(language: String?)

    var isMarkdown: Bool {
        if case .markdown = self { return true }
        return false
    }

    var language: String? {
        if case .text(let language) = self { return language }
        return nil
    }

    var label: String {
        switch self {
        case .markdown: return "Markdown"
        case .text(let language): return language?.uppercased() ?? "Text"
        }
    }
}

enum ScrollSource: Equatable {
    case editor
    case preview
    case outline
}

enum ScrollSyncMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case smart
    case top
    case center
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smart: return "Smart (35%)"
        case .top: return "Top"
        case .center: return "Center"
        case .off: return "Off"
        }
    }

    /// The shared guide line inside each viewport. Keeping this away from the
    /// exact edge leaves enough context to make semantic alignment feel stable.
    var viewportFraction: Double? {
        switch self {
        case .smart: return 0.35
        case .top: return 0.08
        case .center: return 0.5
        case .off: return nil
        }
    }
}

enum ScrollBoundary: String, Equatable {
    case none
    case top
    case bottom
}

struct ScrollPosition: Equatable {
    var line: Int = 0
    var fraction: Double = 0
    var boundary: ScrollBoundary = .none
}

final class ScrollSyncState: ObservableObject {
    @Published var position = ScrollPosition()
    @Published var source: ScrollSource = .editor
}

struct EditorTheme: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var isDark: Bool
    var isBuiltIn: Bool
    var backgroundHex: String
    var foregroundHex: String
    var mutedHex: String
    var lineHex: String
    var accentHex: String
    var codeHex: String
    var syntaxKeywordHex: String
    var syntaxStringHex: String
    var syntaxCommentHex: String
    var syntaxNumberHex: String
    var syntaxTypeHex: String
    var syntaxTagHex: String

    var background: Color { Color(hex: backgroundHex) }
    var foreground: Color { Color(hex: foregroundHex) }
    var accent: Color { Color(hex: accentHex) }

    var css: String {
        "--bg:\(backgroundHex);--fg:\(foregroundHex);--muted:\(mutedHex);--line:\(lineHex);--accent:\(accentHex);--code:\(codeHex);--syn-key:\(syntaxKeywordHex);--syn-string:\(syntaxStringHex);--syn-comment:\(syntaxCommentHex);--syn-number:\(syntaxNumberHex);--syn-type:\(syntaxTypeHex);--syn-tag:\(syntaxTagHex);"
    }

    static let paper = EditorTheme(
        id: "builtin.paper", name: "Mirror Light", isDark: false, isBuiltIn: true,
        backgroundHex: "#FFFFFF", foregroundHex: "#302E2A", mutedHex: "#767066", lineHex: "#D8D2C6",
        accentHex: "#756951", codeHex: "#F0EDE5", syntaxKeywordHex: "#9A4F5D", syntaxStringHex: "#4E7354",
        syntaxCommentHex: "#636366", syntaxNumberHex: "#9B633C", syntaxTypeHex: "#4F6F7A", syntaxTagHex: "#9A5745"
    )
    static let ink = EditorTheme(
        id: "builtin.ink", name: "Mirror Dark", isDark: true, isBuiltIn: true,
        backgroundHex: "#252420", foregroundHex: "#EEEAE0", mutedHex: "#B3ACA0", lineHex: "#514C43",
        accentHex: "#C4B59A", codeHex: "#302E29", syntaxKeywordHex: "#DE9CAC", syntaxStringHex: "#BCD092",
        syntaxCommentHex: "#A79B8F", syntaxNumberHex: "#E3B078", syntaxTypeHex: "#A8C7CC", syntaxTagHex: "#DFA282"
    )
    static let sepia = EditorTheme(
        id: "builtin.sepia", name: "Sepia", isDark: false, isBuiltIn: true,
        backgroundHex: "#F5E9CA", foregroundHex: "#3C3325", mutedHex: "#85745C", lineHex: "#DFCFAA",
        accentHex: "#8B5B32", codeHex: "#EADBB8", syntaxKeywordHex: "#9C3154", syntaxStringHex: "#51722C",
        syntaxCommentHex: "#91816A", syntaxNumberHex: "#9A5718", syntaxTypeHex: "#28647A", syntaxTagHex: "#98472A"
    )
    static let midnight = EditorTheme(
        id: "builtin.midnight", name: "Midnight", isDark: true, isBuiltIn: true,
        backgroundHex: "#16181C", foregroundHex: "#D7DBDF", mutedHex: "#858C94", lineHex: "#2D3138",
        accentHex: "#68C7B3", codeHex: "#22262C", syntaxKeywordHex: "#F08DB2", syntaxStringHex: "#9BD58B",
        syntaxCommentHex: "#77818C", syntaxNumberHex: "#E7AD72", syntaxTypeHex: "#7CCBE5", syntaxTagHex: "#F1A47C"
    )

    static let builtIns: [EditorTheme] = [
        .paper,
        .ink,
        .sepia,
        .midnight,
        EditorTheme(id: "builtin.solarized", name: "Solarized Light", isDark: false, isBuiltIn: true,
                    backgroundHex: "#FDF6E3", foregroundHex: "#586E75", mutedHex: "#839496", lineHex: "#EEE8D5",
                    accentHex: "#268BD2", codeHex: "#EEE8D5", syntaxKeywordHex: "#859900", syntaxStringHex: "#2AA198",
                    syntaxCommentHex: "#93A1A1", syntaxNumberHex: "#D33682", syntaxTypeHex: "#268BD2", syntaxTagHex: "#CB4B16"),
        EditorTheme(id: "builtin.nord", name: "Nord", isDark: true, isBuiltIn: true,
                    backgroundHex: "#2E3440", foregroundHex: "#D8DEE9", mutedHex: "#8993A5", lineHex: "#434C5E",
                    accentHex: "#88C0D0", codeHex: "#3B4252", syntaxKeywordHex: "#B48EAD", syntaxStringHex: "#A3BE8C",
                    syntaxCommentHex: "#7F8A9D", syntaxNumberHex: "#D08770", syntaxTypeHex: "#8FBCBB", syntaxTagHex: "#81A1C1"),
        EditorTheme(id: "builtin.dracula", name: "Dracula", isDark: true, isBuiltIn: true,
                    backgroundHex: "#282A36", foregroundHex: "#F8F8F2", mutedHex: "#9CA0B0", lineHex: "#44475A",
                    accentHex: "#BD93F9", codeHex: "#343746", syntaxKeywordHex: "#FF79C6", syntaxStringHex: "#F1FA8C",
                    syntaxCommentHex: "#6272A4", syntaxNumberHex: "#BD93F9", syntaxTypeHex: "#8BE9FD", syntaxTagHex: "#FFB86C"),
        EditorTheme(id: "builtin.forest", name: "Forest", isDark: true, isBuiltIn: true,
                    backgroundHex: "#17231D", foregroundHex: "#DCE7DF", mutedHex: "#8DA096", lineHex: "#32483C",
                    accentHex: "#78C59A", codeHex: "#223129", syntaxKeywordHex: "#D29BC5", syntaxStringHex: "#A8D18D",
                    syntaxCommentHex: "#71877B", syntaxNumberHex: "#E3B778", syntaxTypeHex: "#7DC9C3", syntaxTagHex: "#E79B77"),
        EditorTheme(id: "builtin.rose", name: "Rose", isDark: false, isBuiltIn: true,
                    backgroundHex: "#FFF8F7", foregroundHex: "#402F32", mutedHex: "#8F7479", lineHex: "#EEDDDD",
                    accentHex: "#B44B68", codeHex: "#F7EAEA", syntaxKeywordHex: "#9B3B72", syntaxStringHex: "#4F7B57",
                    syntaxCommentHex: "#9D8589", syntaxNumberHex: "#B05B32", syntaxTypeHex: "#3E7181", syntaxTagHex: "#A84D45")
    ]
}

struct TypographySettings: Codable, Equatable, Hashable, Sendable {
    var editorFontFamily: String?
    var previewFontFamily: String?
    var codeFontFamily: String?
    var editorFontSize: Double
    var previewFontSize: Double
    var editorLineSpacing: Double
    var previewLineHeight: Double
    var contentWidth: Double

    static let standard = TypographySettings(
        editorFontFamily: nil,
        previewFontFamily: nil,
        codeFontFamily: nil,
        editorFontSize: 16.5,
        previewFontSize: 17,
        editorLineSpacing: 5,
        previewLineHeight: 1.88,
        contentWidth: 720
    )
}

struct EditorBehaviorSettings: Codable, Equatable, Hashable, Sendable {
    var showLineNumbers: Bool
    var highlightCurrentLine: Bool
    var checkSpelling: Bool
    var wordWrap: Bool
    var typewriterMode: Bool
    var scrollSyncMode: ScrollSyncMode
    var preserveSingleLineBreaks: Bool
    var autoPairDelimiters: Bool
    var tabWidth: Int
    var autosaveDelay: Double

    static let standard = EditorBehaviorSettings(
        showLineNumbers: false,
        highlightCurrentLine: true,
        checkSpelling: true,
        wordWrap: true,
        typewriterMode: false,
        scrollSyncMode: .smart,
        preserveSingleLineBreaks: true,
        autoPairDelimiters: true,
        tabWidth: 4,
        autosaveDelay: 1.2
    )

    private enum CodingKeys: String, CodingKey {
        case showLineNumbers, highlightCurrentLine, checkSpelling, wordWrap, typewriterMode, scrollSyncMode
        case preserveSingleLineBreaks, autoPairDelimiters, tabWidth, autosaveDelay
    }

    init(showLineNumbers: Bool,
         highlightCurrentLine: Bool,
         checkSpelling: Bool,
         wordWrap: Bool,
         typewriterMode: Bool,
         scrollSyncMode: ScrollSyncMode,
         preserveSingleLineBreaks: Bool,
         autoPairDelimiters: Bool,
         tabWidth: Int,
         autosaveDelay: Double) {
        self.showLineNumbers = showLineNumbers
        self.highlightCurrentLine = highlightCurrentLine
        self.checkSpelling = checkSpelling
        self.wordWrap = wordWrap
        self.typewriterMode = typewriterMode
        self.scrollSyncMode = scrollSyncMode
        self.preserveSingleLineBreaks = preserveSingleLineBreaks
        self.autoPairDelimiters = autoPairDelimiters
        self.tabWidth = tabWidth
        self.autosaveDelay = autosaveDelay
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        showLineNumbers = try values.decodeIfPresent(Bool.self, forKey: .showLineNumbers) ?? false
        highlightCurrentLine = try values.decodeIfPresent(Bool.self, forKey: .highlightCurrentLine) ?? true
        checkSpelling = try values.decodeIfPresent(Bool.self, forKey: .checkSpelling) ?? true
        wordWrap = try values.decodeIfPresent(Bool.self, forKey: .wordWrap) ?? true
        typewriterMode = try values.decodeIfPresent(Bool.self, forKey: .typewriterMode) ?? false
        scrollSyncMode = try values.decodeIfPresent(ScrollSyncMode.self, forKey: .scrollSyncMode) ?? .smart
        preserveSingleLineBreaks = try values.decodeIfPresent(Bool.self, forKey: .preserveSingleLineBreaks) ?? true
        autoPairDelimiters = try values.decodeIfPresent(Bool.self, forKey: .autoPairDelimiters) ?? true
        tabWidth = try values.decodeIfPresent(Int.self, forKey: .tabWidth) ?? 4
        autosaveDelay = try values.decodeIfPresent(Double.self, forKey: .autosaveDelay) ?? 1.2
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let divisor = 255.0
        switch value.count {
        case 8:
            self.init(.sRGB,
                      red: Double((number >> 24) & 0xFF) / divisor,
                      green: Double((number >> 16) & 0xFF) / divisor,
                      blue: Double((number >> 8) & 0xFF) / divisor,
                      opacity: Double(number & 0xFF) / divisor)
        default:
            self.init(.sRGB,
                      red: Double((number >> 16) & 0xFF) / divisor,
                      green: Double((number >> 8) & 0xFF) / divisor,
                      blue: Double(number & 0xFF) / divisor,
                      opacity: 1)
        }
    }
}

struct WritingStats: Sendable {
    let words: Int
    let characters: Int
    let minutes: Int

    init(text: String) {
        characters = text.count
        let latin = text.split { $0.isWhitespace || $0.isPunctuation }.count
        let cjk = text.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
        words = latin + cjk
        minutes = max(1, Int(ceil(Double(max(words, 1)) / 250.0)))
    }
}

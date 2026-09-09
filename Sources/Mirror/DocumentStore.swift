import AppKit
import Combine
import CoreFoundation
import UniformTypeIdentifiers

@MainActor
final class DocumentStore: ObservableObject {
    @Published var text: String = DocumentStore.welcomeText {
        didSet {
            guard text != oldValue else { return }
            textRevision &+= 1
            guard !isLoading else { return }
            scheduleDocumentAnalysis()
            if !isDirty { isDirty = true }
            scheduleAutosave()
            scheduleRecoverySnapshot()
        }
    }
    @Published var fileURL: URL?
    @Published private(set) var documentFormat: EditableDocumentFormat = .markdown
    @Published var lineEnding: DocumentLineEnding = .lf {
        didSet {
            guard lineEnding != oldValue, !isSwitchingTabs else { return }
            isDirty = true
            syncCurrentTab()
            scheduleAutosave()
            scheduleRecoverySnapshot()
        }
    }
    @Published private(set) var textRevision = 0
    @Published var isDirty = false
    @Published var showSidebar = true
    @Published var showFileLibrary = false
    @Published var showOutline = true
    @Published var showPreview = true
    @Published var focusMode = false
    @Published var readerMode = false
    @Published var theme: EditorTheme = .paper {
        didSet { persistAppearanceIfReady() }
    }
    @Published var typography: TypographySettings = .standard {
        didSet { persistAppearanceIfReady() }
    }
    @Published var editorSettings: EditorBehaviorSettings = .standard {
        didSet { persistAppearanceIfReady() }
    }
    @Published private(set) var customThemes: [EditorTheme] = []
    @Published private(set) var availableFontFamilies: [String] = []
    @Published private(set) var importedFonts: [URL] = []
    @Published var selectedRange = NSRange(location: 0, length: 0)
    @Published var editorCommand: EditorCommand?
    @Published var notice: String?
    @Published private(set) var recentFiles: [URL]
    @Published private(set) var headings: [Heading] = DocumentStore.extractHeadings(from: DocumentStore.welcomeText)
    @Published private(set) var stats = WritingStats(text: DocumentStore.welcomeText)
    @Published private(set) var workspaceURL: URL?
    @Published private(set) var workspaceFiles: [URL] = []
    @Published private(set) var workspaceTree: [WorkspaceNode] = []
    @Published private(set) var markdownWorkspaceTree: [WorkspaceNode] = []
    @Published private(set) var markdownFileCount = 0
    @Published private(set) var isLoadingWorkspace = false
    @Published var showMarkdownOnly = false
    @Published var showQuickOpen = false
    @Published var showWorkspaceSearch = false
    @Published var showCommandPalette = false
    @Published var showDocumentHistory = false
    @Published var showTableBuilder = false
    @Published private(set) var workspaceSearchResults: [WorkspaceSearchResult] = []
    @Published private(set) var isSearchingWorkspace = false
    @Published private(set) var workspaceSearchError: String?
    @Published private(set) var documentHistory: [DocumentHistoryEntry] = []
    @Published private(set) var isLoadingDocumentHistory = false
    @Published private(set) var isExportingDocument = false
    @Published private(set) var previewFileURL: URL?
    @Published private(set) var openTabs: [OpenDocumentTab] = []
    @Published private(set) var activeTabID: UUID?
    @Published private(set) var externalConflict: ExternalFileConflict?

    private var isLoading = false
    private var isLoadingAppearance = true
    private var textEncoding: String.Encoding = .utf8
    private var autosaveTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var documentAnalysisTask: Task<Void, Never>?
    private var markdownExporter: MarkdownFileExporter?
    private var isSwitchingTabs = false
    private var fileRevision: FileRevision?
    private var externalMonitorTask: Task<Void, Never>?
    private var workspaceSearchTask: Task<Void, Never>?
    private var documentHistoryTask: Task<Void, Never>?
    private var workspaceSearchID = UUID()
    private var workspaceRefreshID = UUID()

    init() {
        LegacyBrandMigration.performIfNeeded()
        let appearance = AppearanceManager.load()
        theme = appearance.theme
        typography = appearance.typography
        editorSettings = appearance.editor
        customThemes = appearance.customThemes
        availableFontFamilies = AppearanceManager.fontFamilies
        importedFonts = AppearanceManager.importedFontURLs
        isLoadingAppearance = false
        recentFiles = Self.loadRecentFiles()
        previewFileURL = nil
        if let path = UserDefaults.standard.string(forKey: "MirrorWorkspaceFolder"),
           FileManager.default.fileExists(atPath: path) {
            workspaceURL = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            workspaceURL = nil
        }
        if workspaceURL != nil { Task { refreshWorkspace() } }
        if !restoreRecoverySessionIfAvailable() {
            let initialTab = snapshotCurrentTab()
            openTabs = [initialTab]
            activeTabID = initialTab.id
        }
    }

    var displayURL: URL? { previewFileURL ?? fileURL }
    var title: String { displayURL?.deletingPathExtension().lastPathComponent ?? "Untitled" }
    var displayedWorkspaceTree: [WorkspaceNode] { showMarkdownOnly ? markdownWorkspaceTree : workspaceTree }
    var isMarkdownDocument: Bool { documentFormat.isMarkdown }
    var editorLanguage: String? { documentFormat.language }
    var availableThemes: [EditorTheme] { EditorTheme.builtIns + customThemes }
    var activeTab: OpenDocumentTab? { openTabs.first { $0.id == activeTabID } }
    var selectionStats: WritingStats? {
        guard selectedRange.length > 0,
              selectedRange.location + selectedRange.length <= (text as NSString).length else { return nil }
        return WritingStats(text: (text as NSString).substring(with: selectedRange))
    }
    var encodingLabel: String {
        switch textEncoding {
        case .utf8: return "UTF-8"
        case .utf16: return "UTF-16"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian: return "UTF-16 BE"
        case .windowsCP1252: return "Windows-1252"
        case .isoLatin1: return "ISO Latin-1"
        case .macOSRoman: return "Mac Roman"
        default: return "GB18030"
        }
    }
    var encodingChoices: [TextEncodingChoice] { TextEncodingChoice.common }

    func selectEncoding(_ rawValue: UInt) {
        let selected = String.Encoding(rawValue: rawValue)
        guard selected != textEncoding, previewFileURL == nil else { return }
        textEncoding = selected
        isDirty = true
        syncCurrentTab()
        scheduleAutosave()
        scheduleRecoverySnapshot()
    }
    private nonisolated static func extractHeadings(from text: String) -> [Heading] {
        let lines = text.components(separatedBy: .newlines)
        var result: [Heading] = []
        var fence: (character: Character, count: Int)?
        var index = 0
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix { $0 == first }.count
                if count >= 3 {
                    let suffix = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
                    if let active = fence {
                        if first == active.character, count >= active.count, suffix.isEmpty { fence = nil }
                    } else {
                        fence = (first, count)
                    }
                    index += 1
                    continue
                }
            }
            guard fence == nil else { index += 1; continue }
            let marks = trimmed.prefix { $0 == "#" }
            if !marks.isEmpty, marks.count <= 6, trimmed.dropFirst(marks.count).first == " " {
                result.append(Heading(level: marks.count,
                                      title: trimmed.dropFirst(marks.count + 1).trimmingCharacters(in: .whitespaces),
                                      line: index))
            } else if !trimmed.isEmpty, index + 1 < lines.count {
                let underline = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if underline.range(of: #"^=+\s*$"#, options: .regularExpression) != nil {
                    result.append(Heading(level: 1, title: trimmed, line: index)); index += 1
                } else if underline.range(of: #"^-+\s*$"#, options: .regularExpression) != nil {
                    result.append(Heading(level: 2, title: trimmed, line: index)); index += 1
                }
            }
            index += 1
        }
        return result
    }
    func selectTheme(_ selected: EditorTheme) {
        theme = selected
    }

    @discardableResult
    func duplicateTheme(_ source: EditorTheme) -> EditorTheme {
        var copy = source
        copy.id = "custom.\(UUID().uuidString.lowercased())"
        copy.name = uniqueThemeName("\(source.name) Custom")
        copy.isBuiltIn = false
        customThemes.append(copy)
        theme = copy
        persistAppearanceIfReady()
        return copy
    }

    func saveCustomTheme(_ value: EditorTheme) {
        var custom = value
        custom.isBuiltIn = false
        if let index = customThemes.firstIndex(where: { $0.id == custom.id }) {
            customThemes[index] = custom
        } else {
            custom.id = "custom.\(UUID().uuidString.lowercased())"
            custom.name = uniqueThemeName(custom.name)
            customThemes.append(custom)
        }
        theme = custom
        persistAppearanceIfReady()
    }

    func deleteCustomTheme(_ value: EditorTheme) {
        guard !value.isBuiltIn else { return }
        customThemes.removeAll { $0.id == value.id }
        if theme.id == value.id { theme = .paper }
        persistAppearanceIfReady()
    }

    func importThemes() {
        let panel = NSOpenPanel()
        panel.title = "Import Mirror Themes"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK else { return }
        do {
            let decoder = JSONDecoder()
            var imported: [EditorTheme] = []
            for url in panel.urls {
                let data = try Data(contentsOf: url)
                let decoded: [EditorTheme]
                if let collection = try? decoder.decode([EditorTheme].self, from: data) {
                    decoded = collection
                } else {
                    decoded = [try decoder.decode(EditorTheme.self, from: data)]
                }
                for var item in decoded where Self.isValidTheme(item) {
                    item.id = "custom.\(UUID().uuidString.lowercased())"
                    item.name = uniqueThemeName(item.name)
                    item.isBuiltIn = false
                    imported.append(item)
                }
            }
            guard !imported.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            customThemes.append(contentsOf: imported)
            theme = imported[0]
            persistAppearanceIfReady()
            flash("Imported \(imported.count) theme\(imported.count == 1 ? "" : "s")")
        } catch {
            showError("Couldn’t import the theme", error)
        }
    }

    func exportTheme(_ value: EditorTheme) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(value.name).mirror-theme.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
            flash("Exported \(url.lastPathComponent)")
        } catch {
            showError("Couldn’t export the theme", error)
        }
    }

    func importFonts() {
        do {
            let imported = try AppearanceManager.importFonts()
            guard !imported.isEmpty else { return }
            reloadFonts()
            flash("Imported \(imported.count) font file\(imported.count == 1 ? "" : "s")")
        } catch {
            showError("Couldn’t import the font", error)
        }
    }

    func removeImportedFont(_ url: URL) {
        AppearanceManager.removeImportedFont(url) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.showError("Couldn’t remove the font", error)
                } else {
                    self.reloadFonts()
                    self.flash("Moved \(url.lastPathComponent) to Trash")
                }
            }
        }
    }

    func resetTypography() {
        typography = .standard
    }

    func resetEditorSettings() {
        editorSettings = .standard
    }

    private func reloadFonts() {
        availableFontFamilies = AppearanceManager.fontFamilies
        importedFonts = AppearanceManager.importedFontURLs
    }

    private func persistAppearanceIfReady() {
        guard !isLoadingAppearance else { return }
        AppearanceManager.save(theme: theme, typography: typography, editor: editorSettings, customThemes: customThemes)
    }

    private func uniqueThemeName(_ requested: String) -> String {
        let base = requested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Theme" : requested
        let existing = Set(availableThemes.map { $0.name.lowercased() })
        guard existing.contains(base.lowercased()) else { return base }
        var index = 2
        while existing.contains("\(base) \(index)".lowercased()) { index += 1 }
        return "\(base) \(index)"
    }

    private nonisolated static func isValidTheme(_ theme: EditorTheme) -> Bool {
        let colors = [theme.backgroundHex, theme.foregroundHex, theme.mutedHex, theme.lineHex, theme.accentHex,
                      theme.codeHex, theme.syntaxKeywordHex, theme.syntaxStringHex, theme.syntaxCommentHex,
                      theme.syntaxNumberHex, theme.syntaxTypeHex, theme.syntaxTagHex]
        return !theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && colors.allSatisfy {
            $0.range(of: #"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$"#, options: .regularExpression) != nil
        }
    }

    private func snapshotCurrentTab(id: UUID? = nil) -> OpenDocumentTab {
        OpenDocumentTab(id: id ?? activeTabID ?? UUID(),
                        text: text,
                        filePath: fileURL?.path,
                        previewPath: previewFileURL?.path,
                        encodingRawValue: textEncoding.rawValue,
                        lineEndingRawValue: lineEnding.rawValue,
                        fileRevision: fileRevision,
                        isDirty: isDirty,
                        selectionLocation: selectedRange.location,
                        selectionLength: selectedRange.length,
                        readerMode: readerMode)
    }

    private func syncCurrentTab() {
        guard !isSwitchingTabs,
              let id = activeTabID,
              let index = openTabs.firstIndex(where: { $0.id == id }) else { return }
        openTabs[index] = snapshotCurrentTab(id: id)
    }

    @discardableResult
    private func prepareCurrentTabForSwitch() -> Bool {
        autosaveTask?.cancel()
        guard externalConflict == nil else {
            flash("Resolve the external file conflict before switching tabs")
            return false
        }
        if isDirty, let fileURL {
            if let expected = fileRevision {
                guard let reconciled = Self.reconciledFileRevision(at: fileURL, expected: expected) else {
                    presentExternalConflict(for: fileURL)
                    return false
                }
                fileRevision = reconciled
            }
            do {
                let serialized = serializedText(text)
                try serialized.write(to: fileURL, atomically: true, encoding: textEncoding)
                fileRevision = Self.fileRevisionAfterWrite(at: fileURL, text: serialized, encoding: textEncoding)
                isDirty = false
                let historyText = text
                let historyEncoding = textEncoding
                let historyLineEnding = lineEnding
                Task.detached(priority: .utility) {
                    Self.archiveHistorySnapshot(url: fileURL, text: historyText, encoding: historyEncoding,
                                                lineEnding: historyLineEnding, force: false)
                }
            } catch {
                showError("Couldn’t autosave before switching tabs", error)
                return false
            }
        }
        syncCurrentTab()
        return true
    }

    private func loadTab(_ tab: OpenDocumentTab) {
        isSwitchingTabs = true
        isLoading = true
        activeTabID = tab.id
        fileURL = tab.filePath.map { URL(fileURLWithPath: $0).standardizedFileURL }
        previewFileURL = tab.previewPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
        if let fileURL {
            documentFormat = Self.editableFormat(for: fileURL)
        } else {
            documentFormat = .markdown
        }
        textEncoding = String.Encoding(rawValue: tab.encodingRawValue)
        lineEnding = DocumentLineEnding(rawValue: tab.lineEndingRawValue ?? "LF") ?? .lf
        fileRevision = tab.fileRevision
        externalConflict = nil
        text = tab.text
        selectedRange = NSRange(location: min(tab.selectionLocation, (tab.text as NSString).length),
                                length: min(tab.selectionLength, max(0, (tab.text as NSString).length - min(tab.selectionLocation, (tab.text as NSString).length))))
        readerMode = tab.readerMode && documentFormat.isMarkdown && previewFileURL == nil
        headings = documentFormat.isMarkdown ? Self.extractHeadings(from: text) : []
        stats = WritingStats(text: text)
        isDirty = tab.isDirty
        isLoading = false
        isSwitchingTabs = false
        startMonitoringCurrentFile()
    }

    func selectTab(_ id: UUID) {
        guard id != activeTabID, let tab = openTabs.first(where: { $0.id == id }) else { return }
        guard prepareCurrentTabForSwitch() else { return }
        loadTab(tab)
        scheduleRecoverySnapshot()
    }

    func closeTab(_ id: UUID) {
        guard let index = openTabs.firstIndex(where: { $0.id == id }) else { return }
        if activeTabID != id { selectTab(id) }
        guard confirmDiscardIfNeeded() else { return }
        autosaveTask?.cancel()
        openTabs.removeAll { $0.id == id }
        if openTabs.isEmpty {
            let blank = OpenDocumentTab(id: UUID(), text: "# Untitled\n\nStart writing…", filePath: nil,
                                        previewPath: nil, encodingRawValue: String.Encoding.utf8.rawValue,
                                        lineEndingRawValue: DocumentLineEnding.lf.rawValue,
                                        fileRevision: nil,
                                        isDirty: false, selectionLocation: 0, selectionLength: 0, readerMode: false)
            openTabs = [blank]
            loadTab(blank)
        } else {
            loadTab(openTabs[min(index, openTabs.count - 1)])
        }
        scheduleRecoverySnapshot()
    }

    func selectNextTab(offset: Int) {
        guard openTabs.count > 1,
              let id = activeTabID,
              let index = openTabs.firstIndex(where: { $0.id == id }) else { return }
        let next = (index + offset + openTabs.count) % openTabs.count
        selectTab(openTabs[next].id)
    }

    func newDocument() {
        guard prepareCurrentTabForSwitch() else { return }
        let blank = OpenDocumentTab(id: UUID(), text: "# Untitled\n\nStart writing…", filePath: nil,
                                    previewPath: nil, encodingRawValue: String.Encoding.utf8.rawValue,
                                    lineEndingRawValue: DocumentLineEnding.lf.rawValue,
                                    fileRevision: nil,
                                    isDirty: false, selectionLocation: 0, selectionLength: 0, readerMode: false)
        openTabs.append(blank)
        loadTab(blank)
        scheduleRecoverySnapshot()
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFile(url)
    }

    func chooseWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Folder"
        panel.message = "Choose a folder to show its files in Mirror."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openWorkspaceFolder(url)
    }

    func openWorkspaceFolder(_ url: URL) {
        let normalized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            showWorkspaceError("“\(url.lastPathComponent)” is not an available folder.")
            return
        }
        workspaceSearchTask?.cancel()
        workspaceSearchResults = []
        workspaceSearchError = nil
        isSearchingWorkspace = false
        workspaceURL = normalized
        UserDefaults.standard.set(workspaceURL?.path, forKey: "MirrorWorkspaceFolder")
        refreshWorkspace()
    }

    func refreshWorkspace() {
        guard let root = workspaceURL else { workspaceFiles = []; return }
        let refreshID = UUID()
        workspaceRefreshID = refreshID
        isLoadingWorkspace = true
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.enumerateWorkspace(in: root)
            }.value
            guard let self, self.workspaceURL == root, self.workspaceRefreshID == refreshID else { return }
            self.workspaceFiles = snapshot.files
            self.workspaceTree = snapshot.tree
            self.markdownWorkspaceTree = snapshot.markdownTree
            self.markdownFileCount = snapshot.markdownCount
            self.isLoadingWorkspace = false
        }
    }

    func closeWorkspaceFolder() {
        workspaceRefreshID = UUID()
        workspaceSearchTask?.cancel()
        workspaceSearchID = UUID()
        workspaceURL = nil
        workspaceFiles = []
        workspaceTree = []
        markdownWorkspaceTree = []
        markdownFileCount = 0
        isLoadingWorkspace = false
        workspaceSearchResults = []
        workspaceSearchError = nil
        isSearchingWorkspace = false
        UserDefaults.standard.removeObject(forKey: "MirrorWorkspaceFolder")
    }

    func createMarkdownFile(in directory: URL) {
        guard isWorkspaceLocation(directory) else {
            showWorkspaceError("The selected folder is outside the current workspace.")
            return
        }
        let suggested = availableName(base: "Untitled", extension: "md", in: directory)
        guard var name = promptForName(
            title: "New Markdown File",
            message: "Create a Markdown file in \(directory.lastPathComponent).",
            defaultValue: suggested,
            actionTitle: "Create"
        ), let validated = validatedWorkspaceName(name) else { return }
        name = validated
        if URL(fileURLWithPath: name).pathExtension.isEmpty { name += ".md" }
        let destination = directory.appendingPathComponent(name).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            showWorkspaceError("An item named “\(name)” already exists.")
            return
        }
        do {
            let heading = destination.deletingPathExtension().lastPathComponent
            try "# \(heading)\n\n".write(to: destination, atomically: true, encoding: .utf8)
            refreshWorkspace()
            open(url: destination)
            flash("Created \(name)")
        } catch {
            showError("Couldn’t create the file", error)
        }
    }

    func createFolder(in directory: URL) {
        guard isWorkspaceLocation(directory) else {
            showWorkspaceError("The selected folder is outside the current workspace.")
            return
        }
        let suggested = availableName(base: "New Folder", extension: nil, in: directory)
        guard let name = promptForName(
            title: "New Folder",
            message: "Create a folder in \(directory.lastPathComponent).",
            defaultValue: suggested,
            actionTitle: "Create"
        ), let validated = validatedWorkspaceName(name) else { return }
        let destination = directory.appendingPathComponent(validated).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            showWorkspaceError("An item named “\(validated)” already exists.")
            return
        }
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            if showMarkdownOnly { showMarkdownOnly = false }
            refreshWorkspace()
            flash("Created \(validated)")
        } catch {
            showError("Couldn’t create the folder", error)
        }
    }

    func renameWorkspaceItem(_ source: URL) {
        guard isWorkspaceLocation(source), source.standardizedFileURL != workspaceURL?.standardizedFileURL else {
            showWorkspaceError("This item can’t be renamed from the workspace browser.")
            return
        }
        guard let name = promptForName(
            title: "Rename",
            message: "Enter a new name for \(source.lastPathComponent).",
            defaultValue: source.lastPathComponent,
            actionTitle: "Rename"
        ), let validated = validatedWorkspaceName(name) else { return }
        let normalizedSource = source.standardizedFileURL
        let destination = source.deletingLastPathComponent().appendingPathComponent(validated).standardizedFileURL
        guard destination.path != normalizedSource.path else { return }
        let isCaseOnlyRename = destination.path.caseInsensitiveCompare(normalizedSource.path) == .orderedSame
        if !isCaseOnlyRename, FileManager.default.fileExists(atPath: destination.path) {
            showWorkspaceError("An item named “\(validated)” already exists.")
            return
        }

        autosaveTask?.cancel()
        do {
            if isCaseOnlyRename {
                let temporary = source.deletingLastPathComponent()
                    .appendingPathComponent(".mirror-rename-\(UUID().uuidString)")
                try FileManager.default.moveItem(at: normalizedSource, to: temporary)
                do {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                } catch {
                    try? FileManager.default.moveItem(at: temporary, to: normalizedSource)
                    throw error
                }
            } else {
                try FileManager.default.moveItem(at: normalizedSource, to: destination)
            }
            remapReferences(from: normalizedSource, to: destination)
            refreshWorkspace()
            if isDirty, fileURL != nil { scheduleAutosave() }
            flash("Renamed to \(validated)")
        } catch {
            if isDirty, fileURL != nil { scheduleAutosave() }
            showError("Couldn’t rename the item", error)
        }
    }

    func moveWorkspaceItemToTrash(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard isWorkspaceLocation(normalized), normalized != workspaceURL?.standardizedFileURL else {
            showWorkspaceError("This item can’t be removed from the workspace browser.")
            return
        }
        let affectsOpenDocument = openTabs.contains { tab in
            [tab.filePath, tab.previewPath].compactMap { $0 }.contains {
                isSameOrDescendant(URL(fileURLWithPath: $0), of: normalized)
            }
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move “\(url.lastPathComponent)” to Trash?"
        alert.informativeText = affectsOpenDocument
            ? "The current document will remain open as an unsaved document. The item can be restored from Trash."
            : "The item can be restored from Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        autosaveTask?.cancel()
        NSWorkspace.shared.recycle([normalized]) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    if self.isDirty, self.fileURL != nil { self.scheduleAutosave() }
                    self.showError("Couldn’t move the item to Trash", error)
                    return
                }
                if let fileURL = self.fileURL, self.isSameOrDescendant(fileURL, of: normalized) {
                    self.fileURL = nil
                    self.isDirty = true
                }
                if let previewURL = self.previewFileURL, self.isSameOrDescendant(previewURL, of: normalized) {
                    self.previewFileURL = nil
                }
                let activePreviewWasRemoved = self.activeTab.flatMap(\.previewPath).map {
                    self.isSameOrDescendant(URL(fileURLWithPath: $0), of: normalized)
                } == true
                for index in self.openTabs.indices {
                    if let path = self.openTabs[index].filePath,
                       self.isSameOrDescendant(URL(fileURLWithPath: path), of: normalized) {
                        self.openTabs[index].filePath = nil
                        self.openTabs[index].isDirty = true
                    }
                }
                self.openTabs.removeAll { tab in
                    guard let path = tab.previewPath else { return false }
                    return self.isSameOrDescendant(URL(fileURLWithPath: path), of: normalized)
                }
                if activePreviewWasRemoved {
                    if let fallback = self.openTabs.first {
                        self.loadTab(fallback)
                    } else {
                        let blank = OpenDocumentTab(id: UUID(), text: "# Untitled\n\nStart writing…", filePath: nil,
                                                    previewPath: nil, encodingRawValue: String.Encoding.utf8.rawValue,
                                                    lineEndingRawValue: DocumentLineEnding.lf.rawValue,
                                                    fileRevision: nil,
                                                    isDirty: false, selectionLocation: 0, selectionLength: 0, readerMode: false)
                        self.openTabs = [blank]
                        self.loadTab(blank)
                    }
                } else {
                    self.syncCurrentTab()
                }
                self.recentFiles.removeAll { self.isSameOrDescendant($0, of: normalized) }
                self.persistRecentFiles()
                self.refreshWorkspace()
                self.scheduleRecoverySnapshot()
                self.flash("Moved \(url.lastPathComponent) to Trash")
            }
        }
    }

    func handleDroppedWorkspaceItems(_ urls: [URL], into directory: URL) {
        let shouldMove = !urls.isEmpty && urls.allSatisfy(isWorkspaceLocation)
        transferWorkspaceItems(urls, into: directory, move: shouldMove)
    }

    func pasteWorkspaceItems(_ urls: [URL], into directory: URL, move: Bool) {
        transferWorkspaceItems(urls, into: directory, move: move)
    }

    private func transferWorkspaceItems(_ urls: [URL], into directory: URL, move: Bool) {
        var isDirectory: ObjCBool = false
        guard isWorkspaceLocation(directory),
              FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            showWorkspaceError("Choose a folder inside the current workspace as the destination.")
            return
        }

        let sources = normalizedTransferSources(urls)
        guard !sources.isEmpty else { return }
        for source in sources {
            guard FileManager.default.fileExists(atPath: source.path),
                  source.standardizedFileURL != workspaceURL?.standardizedFileURL else {
                showWorkspaceError("One or more selected items are unavailable.")
                return
            }
            var sourceIsDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory)
            if sourceIsDirectory.boolValue, isSameOrDescendant(directory, of: source) {
                showWorkspaceError("A folder can’t be moved or copied into itself.")
                return
            }
        }

        var transfers: [(source: URL, destination: URL)] = []
        var reservedPaths = Set<String>()
        for source in sources {
            if move {
                let destination = directory.appendingPathComponent(source.lastPathComponent).standardizedFileURL
                if destination.path == source.standardizedFileURL.path { continue }
                guard !FileManager.default.fileExists(atPath: destination.path),
                      reservedPaths.insert(destination.path).inserted else {
                    showWorkspaceError("An item named “\(source.lastPathComponent)” already exists in \(directory.lastPathComponent).")
                    return
                }
                transfers.append((source, destination))
            } else {
                let destination = availableCopyDestination(for: source, in: directory, reservedPaths: &reservedPaths)
                transfers.append((source, destination))
            }
        }
        guard !transfers.isEmpty else {
            flash("The selected items are already in this folder")
            return
        }

        autosaveTask?.cancel()
        do {
            for transfer in transfers {
                if move {
                    try FileManager.default.moveItem(at: transfer.source, to: transfer.destination)
                    remapReferences(from: transfer.source, to: transfer.destination)
                } else {
                    try FileManager.default.copyItem(at: transfer.source, to: transfer.destination)
                }
            }
            refreshWorkspace()
            if isDirty, fileURL != nil { scheduleAutosave() }
            flash(move ? "Moved \(transfers.count) item\(transfers.count == 1 ? "" : "s")" : "Pasted \(transfers.count) item\(transfers.count == 1 ? "" : "s")")
        } catch {
            if isDirty, fileURL != nil { scheduleAutosave() }
            refreshWorkspace()
            showError(move ? "Couldn’t move the selected items" : "Couldn’t paste the selected items", error)
        }
    }

    func openWorkspaceFile(_ url: URL) {
        openFile(url)
    }

    var quickOpenFiles: [URL] {
        var seen = Set<String>()
        return (workspaceFiles + recentFiles).filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    func searchWorkspace(_ query: String, caseSensitive: Bool, regularExpression: Bool) {
        workspaceSearchTask?.cancel()
        let searchID = UUID()
        workspaceSearchID = searchID
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            workspaceSearchResults = []
            workspaceSearchError = nil
            isSearchingWorkspace = false
            return
        }
        if regularExpression {
            do {
                _ = try NSRegularExpression(pattern: value, options: caseSensitive ? [] : [.caseInsensitive])
            } catch {
                workspaceSearchResults = []
                workspaceSearchError = error.localizedDescription
                isSearchingWorkspace = false
                return
            }
        }
        let files = workspaceFiles
        workspaceSearchError = nil
        isSearchingWorkspace = true
        workspaceSearchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) {
                Self.findWorkspaceMatches(query: value,
                                          files: files,
                                          caseSensitive: caseSensitive,
                                          regularExpression: regularExpression)
            }.value
            guard !Task.isCancelled, let self, self.workspaceSearchID == searchID else { return }
            self.workspaceSearchResults = results
            self.isSearchingWorkspace = false
        }
    }

    func openWorkspaceSearchResult(_ result: WorkspaceSearchResult) {
        openFile(result.url)
        guard fileURL?.standardizedFileURL == result.url.standardizedFileURL else { return }
        let lines = text.components(separatedBy: .newlines)
        guard result.line >= 0, result.line < lines.count else { return }
        let location = lines.prefix(result.line).reduce(0) { $0 + ($1 as NSString).length + 1 }
        let lineLength = (lines[result.line] as NSString).length
        let column = min(max(0, result.column), lineLength)
        editorCommand = .select(NSRange(location: location + column,
                                        length: min(result.matchLength, max(0, lineLength - column))))
    }

    func isSupportedDocument(_ url: URL) -> Bool {
        Self.isLikelyEditableText(url)
    }

    func isImageFile(_ url: URL) -> Bool {
        Self.isImage(url)
    }

    func openFile(_ url: URL) {
        let normalized = url.standardizedFileURL
        if let tab = openTabs.first(where: { $0.filePath == normalized.path || $0.previewPath == normalized.path }) {
            selectTab(tab.id)
            recordRecent(normalized)
            return
        }
        if Self.isImage(normalized) || Self.isKnownBinary(normalized) {
            previewFile(normalized)
            return
        }
        do {
            let decoded = try Self.readTextFile(normalized)
            applyOpenedText(decoded.text, encoding: decoded.encoding, lineEnding: decoded.lineEnding,
                            revision: decoded.revision, url: normalized)
        } catch {
            if Self.isLikelyEditableText(normalized) {
                showError("Couldn’t open the text file", error)
            } else {
                previewFile(normalized)
            }
        }
    }

    func previewFile(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let normalized = url.standardizedFileURL
        if let tab = openTabs.first(where: { $0.previewPath == normalized.path || $0.filePath == normalized.path }) {
            selectTab(tab.id)
            return
        }
        guard prepareCurrentTabForSwitch() else { return }
        let tab = OpenDocumentTab(id: UUID(), text: "", filePath: nil, previewPath: normalized.path,
                                  encodingRawValue: String.Encoding.utf8.rawValue,
                                  lineEndingRawValue: DocumentLineEnding.lf.rawValue, fileRevision: nil, isDirty: false,
                                  selectionLocation: 0, selectionLength: 0, readerMode: false)
        openTabs.append(tab)
        loadTab(tab)
        recordRecent(url)
        flash("Previewing \(url.lastPathComponent)")
        scheduleRecoverySnapshot()
    }

    func closeFilePreview() {
        if let activeTabID { closeTab(activeTabID) }
    }

    func openInDefaultApp(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func toggleNavigation() {
        if !showSidebar || (!showFileLibrary && !showOutline) {
            showSidebar = true
            showOutline = true
            showFileLibrary = false
        } else {
            showSidebar.toggle()
        }
    }

    func open(url: URL) {
        openFile(url)
    }

    func save() {
        guard let fileURL else { saveAs(); return }
        write(to: fileURL)
    }

    @discardableResult
    func saveAs() -> Bool {
        let panel = NSSavePanel()
        if isMarkdownDocument {
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        }
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "\(title).md"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        fileURL = url
        fileRevision = nil
        documentFormat = Self.editableFormat(for: url)
        headings = documentFormat.isMarkdown ? Self.extractHeadings(from: text) : []
        return write(to: url, force: true)
    }

    func reloadExternalVersion() {
        guard let conflict = externalConflict else { return }
        let url = conflict.url
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Self.readTextFile(url) }
            }.value
            guard let self, self.fileURL == url else { return }
            switch result {
            case .success(let decoded):
                self.isLoading = true
                self.textEncoding = decoded.encoding
                self.lineEnding = decoded.lineEnding
                self.fileRevision = decoded.revision
                self.text = decoded.text
                self.headings = self.documentFormat.isMarkdown ? Self.extractHeadings(from: decoded.text) : []
                self.stats = WritingStats(text: decoded.text)
                self.isDirty = false
                self.isLoading = false
                self.externalConflict = nil
                self.syncCurrentTab()
                self.scheduleRecoverySnapshot()
                self.startMonitoringCurrentFile()
                self.flash("Reloaded changes from disk")
            case .failure(let error):
                self.showError("Couldn’t reload the external version", error)
            }
        }
    }

    func overwriteExternalVersion() {
        guard let url = externalConflict?.url, fileURL == url else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Overwrite the version on disk?"
        alert.informativeText = "Changes made outside Mirror will be permanently replaced by the text currently open in Mirror."
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let disk = try? Self.readTextFile(url) {
            Self.archiveHistorySnapshot(url: url, text: disk.text, encoding: disk.encoding,
                                        lineEnding: disk.lineEnding, force: true)
        }
        write(to: url, force: true)
    }

    func saveConflictAs() {
        guard externalConflict != nil else { return }
        let panel = NSSavePanel()
        if isMarkdownDocument { panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText] }
        let fileExtension = fileURL?.pathExtension.isEmpty == false ? fileURL?.pathExtension ?? "md" : "md"
        panel.nameFieldStringValue = "\(title) Mirror Copy.\(fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        fileRevision = nil
        externalConflict = nil
        documentFormat = Self.editableFormat(for: url)
        write(to: url, force: true)
    }

    func exportHTML() {
        guard isMarkdownDocument, previewFileURL == nil, !isExportingDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(title).html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExportingDocument = true
        flash("Preparing HTML export…")
        Task { [weak self] in
            guard let self else { return }
            let document = await self.makePortableExportDocument()
            let result = await Task.detached(priority: .userInitiated) {
                Result { try document.html.write(to: url, atomically: true, encoding: .utf8) }
            }.value
            self.isExportingDocument = false
            switch result {
            case .success:
                self.flash(self.exportSuccessMessage(for: url, document: document))
            case .failure(let error):
                self.showError("Couldn’t export HTML", error)
            }
        }
    }

    func exportPDF() {
        guard isMarkdownDocument, previewFileURL == nil, !isExportingDocument else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(title).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startRenderedExport(.pdf(url))
    }

    func printDocument() {
        guard isMarkdownDocument, previewFileURL == nil, !isExportingDocument else { return }
        startRenderedExport(.printDocument)
    }

    private func startRenderedExport(_ operation: MarkdownFileExporter.Operation) {
        guard !isExportingDocument else { return }
        let exportBaseURL = fileURL?.deletingLastPathComponent()
        isExportingDocument = true
        flash(operation.isPrint ? "Preparing print…" : "Preparing PDF export…")
        Task { [weak self] in
            guard let self else { return }
            let document = await self.makePortableExportDocument()
            self.markdownExporter = MarkdownFileExporter(html: document.html,
                                                         baseURL: exportBaseURL,
                                                         operation: operation) { [weak self] result in
                guard let self else { return }
                self.markdownExporter = nil
                self.isExportingDocument = false
                switch result {
                case .success(let url):
                    if let url {
                        self.flash(self.exportSuccessMessage(for: url, document: document))
                    } else {
                        self.flash("Sent to printer")
                    }
                case .failure(let error as CocoaError) where error.code == .userCancelled:
                    break
                case .failure(let error):
                    self.showError("Couldn’t finish the rendered export", error)
                }
            }
        }
    }

    private func makePortableExportDocument() async -> PortableHTMLDocument {
        let markdown = text
        let documentTitle = title
        let selectedTheme = theme
        let selectedTypography = typography
        let preserveSingleLineBreaks = editorSettings.preserveSingleLineBreaks
        let baseURL = fileURL?.deletingLastPathComponent()
        return await Task.detached(priority: .userInitiated) {
            let html = MarkdownRenderer.document(markdown: markdown,
                                                 title: documentTitle,
                                                 theme: selectedTheme,
                                                 typography: selectedTypography,
                                                 preserveSingleLineBreaks: preserveSingleLineBreaks,
                                                 embeddedMermaidScript: MermaidRuntime.script,
                                                 embeddedMathScript: MathRuntime.script)
            return MarkdownExportResources.makePortable(html, baseURL: baseURL)
        }.value
    }

    private func exportSuccessMessage(for url: URL, document: PortableHTMLDocument) -> String {
        guard document.skippedResourceCount > 0 else { return "Exported \(url.lastPathComponent)" }
        return "Exported \(url.lastPathComponent); \(document.skippedResourceCount) large or unavailable media file(s) remain linked"
    }

    func insert(prefix: String) {
        editorCommand = .insert(prefix)
    }

    func wrapSelection(left: String, right: String, placeholder: String) {
        editorCommand = .wrap(left: left, right: right, placeholder: placeholder)
    }

    func insertMarkdownTable(columns: Int, bodyRows: Int, alignments: [MarkdownTableAlignment]) {
        guard isMarkdownDocument, previewFileURL == nil, !readerMode else { return }
        let columnCount = min(10, max(2, columns))
        let rowCount = min(20, max(1, bodyRows))
        let resolvedAlignments = (0..<columnCount).map { index in
            index < alignments.count ? alignments[index] : .leading
        }
        let header = "| " + (1...columnCount).map { "Column \($0)" }.joined(separator: " | ") + " |"
        let delimiter = "| " + resolvedAlignments.map(\.marker).joined(separator: " | ") + " |"
        let row = "| " + Array(repeating: "", count: columnCount).joined(separator: " | ") + " |"
        var table = ([header, delimiter] + Array(repeating: row, count: rowCount)).joined(separator: "\n")

        let source = text as NSString
        let range = selectedRange.location + selectedRange.length <= source.length
            ? selectedRange
            : NSRange(location: min(selectedRange.location, source.length), length: 0)
        if range.location > 0, source.character(at: range.location - 1) != 10 { table = "\n\n" + table }
        if range.location + range.length < source.length, source.character(at: range.location + range.length) != 10 {
            table += "\n\n"
        } else {
            table += "\n"
        }
        editorCommand = .insertAtSelection(table)
    }

    func chooseImagesToInsert() {
        guard isMarkdownDocument, previewFileURL == nil, !readerMode else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.prompt = "Insert"
        panel.message = "Images are copied into an assets folder beside the Markdown file."
        guard panel.runModal() == .OK else { return }
        _ = insertImageFiles(panel.urls)
    }

    @discardableResult
    func insertImageFiles(_ urls: [URL]) -> Bool {
        guard isMarkdownDocument, previewFileURL == nil, !readerMode else { return false }
        let images = urls.map(\.standardizedFileURL).filter(Self.isImage)
        guard !images.isEmpty else { return false }
        guard ensureDocumentSavedForAttachments(), let documentURL = fileURL else { return false }
        do {
            let assetDirectory = try prepareAssetDirectory(for: documentURL)
            var snippets: [String] = []
            for source in images {
                let destination: URL
                if source.deletingLastPathComponent().standardizedFileURL == assetDirectory.standardizedFileURL {
                    destination = source
                } else {
                    destination = availableAttachmentDestination(named: source.lastPathComponent, in: assetDirectory)
                    try FileManager.default.copyItem(at: source, to: destination)
                }
                snippets.append(markdownImageReference(to: destination))
            }
            editorCommand = .insertAtSelection(snippets.joined(separator: "\n"))
            refreshWorkspaceIfNeeded(for: assetDirectory)
            flash("Inserted \(snippets.count) image\(snippets.count == 1 ? "" : "s")")
            return true
        } catch {
            showError("Couldn’t insert the image", error)
            return false
        }
    }

    @discardableResult
    func insertPastedImage(_ image: NSImage) -> Bool {
        guard isMarkdownDocument, previewFileURL == nil, !readerMode else { return false }
        guard ensureDocumentSavedForAttachments(), let documentURL = fileURL else { return false }
        do {
            let assetDirectory = try prepareAssetDirectory(for: documentURL)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let name = "Pasted Image \(formatter.string(from: Date())).png"
            let destination = availableAttachmentDestination(named: name, in: assetDirectory)
            guard let tiff = image.tiffRepresentation,
                  let representation = NSBitmapImageRep(data: tiff),
                  let data = representation.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: destination, options: .atomic)
            editorCommand = .insertAtSelection(markdownImageReference(to: destination))
            refreshWorkspaceIfNeeded(for: assetDirectory)
            flash("Pasted image into assets")
            return true
        } catch {
            showError("Couldn’t paste the image", error)
            return false
        }
    }

    private func ensureDocumentSavedForAttachments() -> Bool {
        fileURL != nil || saveAs()
    }

    private func prepareAssetDirectory(for documentURL: URL) throws -> URL {
        let directory = documentURL.deletingLastPathComponent().appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.standardizedFileURL
    }

    private func availableAttachmentDestination(named requestedName: String, in directory: URL) -> URL {
        let source = URL(fileURLWithPath: requestedName)
        let fileExtension = source.pathExtension
        let stem = source.deletingPathExtension().lastPathComponent.isEmpty
            ? "Image"
            : source.deletingPathExtension().lastPathComponent
        var index = 0
        while true {
            let suffix = index == 0 ? "" : " \(index + 1)"
            let name = fileExtension.isEmpty ? stem + suffix : stem + suffix + "." + fileExtension
            let candidate = directory.appendingPathComponent(name).standardizedFileURL
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func markdownImageReference(to imageURL: URL) -> String {
        let relative = "assets/" + imageURL.lastPathComponent
        let portablePathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~/"))
        let encodedPath = relative.addingPercentEncoding(withAllowedCharacters: portablePathCharacters) ?? relative
        let alt = imageURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        return "![\(alt)](\(encodedPath))"
    }

    private func refreshWorkspaceIfNeeded(for directory: URL) {
        guard let root = workspaceURL else { return }
        let path = directory.standardizedFileURL.path
        if path == root.path || path.hasPrefix(root.path + "/") { refreshWorkspace() }
    }

    func showFind() {
        guard previewFileURL == nil, !readerMode else { return }
        editorCommand = .showFind
    }

    func showReplace() {
        guard previewFileURL == nil, !readerMode else { return }
        editorCommand = .showReplace
    }

    func goToLine() {
        guard previewFileURL == nil, !readerMode else { return }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
        field.placeholderString = "Line number"
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.informativeText = "Enter a line number between 1 and \(max(1, text.components(separatedBy: .newlines).count))."
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let requested = Int(field.stringValue) else { return }
        let lines = text.components(separatedBy: .newlines)
        let line = min(max(0, requested - 1), max(0, lines.count - 1))
        let location = lines.prefix(line).reduce(0) { $0 + ($1 as NSString).length + 1 }
        editorCommand = .select(NSRange(location: location, length: (lines[line] as NSString).length))
    }

    func jump(to heading: Heading) {
        let lines = text.components(separatedBy: .newlines)
        let location = lines.prefix(heading.line).reduce(0) { $0 + ($1 as NSString).length + 1 }
        editorCommand = .select(NSRange(location: location, length: (lines[heading.line] as NSString).length))
    }

    func toggleReaderMode() {
        guard isMarkdownDocument else { return }
        readerMode.toggle()
        if readerMode { focusMode = false }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func removeRecent(_ url: URL) {
        recentFiles.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        persistRecentFiles()
    }

    func clearRecentFiles() {
        recentFiles.removeAll()
        persistRecentFiles()
    }

    func loadDocumentHistory() {
        documentHistoryTask?.cancel()
        guard let url = fileURL, previewFileURL == nil else {
            documentHistory = []
            isLoadingDocumentHistory = false
            return
        }
        isLoadingDocumentHistory = true
        documentHistoryTask = Task { [weak self] in
            let entries = await Task.detached(priority: .userInitiated) {
                Self.readDocumentHistory(for: url)
            }.value
            guard !Task.isCancelled, let self, self.fileURL?.standardizedFileURL == url.standardizedFileURL else { return }
            self.documentHistory = entries
            self.isLoadingDocumentHistory = false
        }
    }

    func restoreDocumentHistory(_ entry: DocumentHistoryEntry) {
        guard let url = fileURL,
              previewFileURL == nil,
              url.standardizedFileURL.path == URL(fileURLWithPath: entry.originalPath).standardizedFileURL.path,
              externalConflict == nil else { return }
        Self.archiveHistorySnapshot(url: url, text: text, encoding: textEncoding,
                                    lineEnding: lineEnding, force: true)
        isSwitchingTabs = true
        isLoading = true
        textEncoding = String.Encoding(rawValue: entry.encodingRawValue)
        lineEnding = DocumentLineEnding(rawValue: entry.lineEndingRawValue) ?? .lf
        text = entry.text
        selectedRange = NSRange(location: 0, length: 0)
        headings = documentFormat.isMarkdown ? Self.extractHeadings(from: entry.text) : []
        stats = WritingStats(text: entry.text)
        isDirty = true
        isLoading = false
        isSwitchingTabs = false
        syncCurrentTab()
        scheduleAutosave()
        scheduleRecoverySnapshot()
        flash("Restored version from \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
    }

    func clearDocumentHistory() {
        guard let url = fileURL else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear history for \(url.lastPathComponent)?"
        alert.informativeText = "Saved versions for this document will be permanently removed. The current document is not affected."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let directory = try Self.historyDirectoryURL(for: url, create: false)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            documentHistory = []
            flash("Cleared document history")
        } catch {
            showError("Couldn’t clear document history", error)
        }
    }

    func revealDocumentHistoryFolder() {
        guard let url = fileURL,
              let directory = try? Self.historyDirectoryURL(for: url, create: true) else { return }
        NSWorkspace.shared.open(directory)
    }

    @discardableResult
    private func write(to url: URL, force: Bool = false) -> Bool {
        if !force, url.standardizedFileURL == fileURL?.standardizedFileURL,
           let expected = fileRevision {
            guard let reconciled = Self.reconciledFileRevision(at: url, expected: expected) else {
                presentExternalConflict(for: url)
                return false
            }
            fileRevision = reconciled
        }
        do {
            let serialized = serializedText(text)
            try serialized.write(to: url, atomically: true, encoding: textEncoding)
            fileRevision = Self.fileRevisionAfterWrite(at: url, text: serialized, encoding: textEncoding)
            isDirty = false
            Self.archiveHistorySnapshot(url: url, text: text, encoding: textEncoding,
                                        lineEnding: lineEnding, force: true)
            externalConflict = nil
            syncCurrentTab()
            scheduleRecoverySnapshot()
            startMonitoringCurrentFile()
            recordRecent(url)
            flash("Saved")
            return true
        } catch {
            showError("Couldn’t save the document", error)
            return false
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard let url = fileURL, externalConflict == nil else { return }
        let editorSnapshot = text
        let snapshot = serializedText(editorSnapshot)
        let encoding = textEncoding
        let historyLineEnding = lineEnding
        let delay = editorSettings.autosaveDelay
        let expectedRevision = fileRevision
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) { () -> AutosaveResult in
                if let expectedRevision,
                   Self.reconciledFileRevision(at: url, expected: expectedRevision) == nil {
                    return .conflict
                }
                do {
                    try snapshot.write(to: url, atomically: true, encoding: encoding)
                    Self.archiveHistorySnapshot(url: url, text: editorSnapshot, encoding: encoding,
                                                lineEnding: historyLineEnding, force: false)
                    return .saved(Self.fileRevisionAfterWrite(at: url, text: snapshot, encoding: encoding))
                } catch {
                    return .failed
                }
            }.value
            guard let self, self.fileURL == url else { return }
            switch result {
            case .saved(let revision) where self.text == editorSnapshot:
                self.fileRevision = revision
                self.isDirty = false
                self.syncCurrentTab()
                self.scheduleRecoverySnapshot()
            case .conflict:
                self.presentExternalConflict(for: url)
            default:
                break
            }
        }
    }

    private enum AutosaveResult: Sendable {
        case saved(FileRevision?)
        case conflict
        case failed
    }

    private nonisolated static func archiveHistorySnapshot(url: URL,
                                                           text: String,
                                                           encoding: String.Encoding,
                                                           lineEnding: DocumentLineEnding,
                                                           force: Bool) {
        let maximumSnapshotBytes = 8 * 1_024 * 1_024
        guard text.lengthOfBytes(using: .utf8) <= maximumSnapshotBytes else { return }
        do {
            let directory = try historyDirectoryURL(for: url, create: true)
            let existing = historyFiles(in: directory)
            if let latestURL = existing.first,
               let data = try? Data(contentsOf: latestURL),
               let latest = try? JSONDecoder().decode(DocumentHistoryEntry.self, from: data) {
                if latest.text == text { return }
                if !force, Date().timeIntervalSince(latest.createdAt) < 120 { return }
            }
            let entry = DocumentHistoryEntry(id: UUID(),
                                             originalPath: url.standardizedFileURL.path,
                                             createdAt: Date(),
                                             text: text,
                                             encodingRawValue: encoding.rawValue,
                                             lineEndingRawValue: lineEnding.rawValue)
            let milliseconds = Int(entry.createdAt.timeIntervalSince1970 * 1_000)
            let destination = directory.appendingPathComponent("\(milliseconds)-\(entry.id.uuidString).json")
            try JSONEncoder().encode(entry).write(to: destination, options: .atomic)
            pruneDocumentHistory(in: directory)
        } catch {
            NSLog("Mirror could not archive document history: %@", error.localizedDescription)
        }
    }

    private nonisolated static func readDocumentHistory(for url: URL) -> [DocumentHistoryEntry] {
        guard let directory = try? historyDirectoryURL(for: url, create: false) else { return [] }
        let path = url.standardizedFileURL.path
        return historyFiles(in: directory).compactMap { file in
            guard let data = try? Data(contentsOf: file),
                  let entry = try? JSONDecoder().decode(DocumentHistoryEntry.self, from: data),
                  entry.originalPath == path else { return nil }
            return entry
        }.sorted { $0.createdAt > $1.createdAt }
    }

    private nonisolated static func historyDirectoryURL(for url: URL, create: Bool) throws -> URL {
        let root = try historyRootURL(create: create)
        let directory = root.appendingPathComponent(historyPathKey(url.standardizedFileURL.path), isDirectory: true)
        if create { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        return directory
    }

    private nonisolated static func historyRootURL(create: Bool) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: create)
        let root = support.appendingPathComponent("Mirror/History", isDirectory: true)
        if create { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        return root
    }

    private nonisolated static func historyPathKey(_ path: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private nonisolated static func historyFiles(in directory: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted {
            let left = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            return left > right
        }
    }

    private nonisolated static func pruneDocumentHistory(in directory: URL) {
        let maximumEntries = 30
        let maximumBytes = 64 * 1_024 * 1_024
        var retainedBytes = 0
        for (index, file) in historyFiles(in: directory).enumerated() {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if index >= maximumEntries || retainedBytes + size > maximumBytes {
                try? FileManager.default.removeItem(at: file)
            } else {
                retainedBytes += size
            }
        }
    }

    private nonisolated static func migrateDocumentHistoryReferences(from source: URL, to destination: URL) {
        guard let root = try? historyRootURL(create: false),
              let directories = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let sourcePath = source.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        var touchedDirectories = Set<URL>()
        for directory in directories {
            for file in historyFiles(in: directory) {
                guard let data = try? Data(contentsOf: file),
                      let entry = try? JSONDecoder().decode(DocumentHistoryEntry.self, from: data),
                      entry.originalPath == sourcePath || entry.originalPath.hasPrefix(sourcePath + "/") else { continue }
                let suffix = String(entry.originalPath.dropFirst(sourcePath.count))
                let mappedPath = destinationPath + suffix
                let mapped = DocumentHistoryEntry(id: entry.id,
                                                  originalPath: mappedPath,
                                                  createdAt: entry.createdAt,
                                                  text: entry.text,
                                                  encodingRawValue: entry.encodingRawValue,
                                                  lineEndingRawValue: entry.lineEndingRawValue)
                guard let targetDirectory = try? historyDirectoryURL(
                    for: URL(fileURLWithPath: mappedPath), create: true
                ) else { continue }
                let target = targetDirectory.appendingPathComponent(file.lastPathComponent)
                do {
                    try JSONEncoder().encode(mapped).write(to: target, options: .atomic)
                    if target.standardizedFileURL != file.standardizedFileURL {
                        try? FileManager.default.removeItem(at: file)
                    }
                    touchedDirectories.insert(targetDirectory)
                } catch {
                    NSLog("Mirror could not migrate document history: %@", error.localizedDescription)
                }
            }
            if (try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        for directory in touchedDirectories { pruneDocumentHistory(in: directory) }
    }

    private func presentExternalConflict(for url: URL) {
        guard fileURL?.standardizedFileURL == url.standardizedFileURL else { return }
        autosaveTask?.cancel()
        if externalConflict?.url.standardizedFileURL != url.standardizedFileURL {
            externalConflict = ExternalFileConflict(url: url.standardizedFileURL, detectedAt: Date())
        }
        flash("This file changed outside Mirror")
    }

    private func startMonitoringCurrentFile() {
        externalMonitorTask?.cancel()
        externalMonitorTask = nil
        guard let url = fileURL, previewFileURL == nil, fileRevision != nil else { return }
        externalMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.fileURL == url,
                      let expected = self.fileRevision else { return }
                let reconciled = await Task.detached(priority: .utility) {
                    Self.reconciledFileRevision(at: url, expected: expected)
                }.value
                guard !Task.isCancelled else { return }
                if let reconciled {
                    if reconciled != expected { self.fileRevision = reconciled; self.syncCurrentTab() }
                    continue
                }
                if self.isDirty {
                    self.presentExternalConflict(for: url)
                } else {
                    self.externalConflict = ExternalFileConflict(url: url, detectedAt: Date())
                    self.reloadExternalVersion()
                }
                return
            }
        }
    }

    private struct RecoverySnapshot: Codable, Sendable {
        let text: String
        let filePath: String?
        let encodingRawValue: UInt
        let savedAt: Date
    }

    private struct RecoverySession: Codable, Sendable {
        let version: Int
        let tabs: [OpenDocumentTab]
        let activeTabID: UUID?
        let savedAt: Date
    }

    func persistForApplicationTermination() {
        autosaveTask?.cancel()
        recoveryTask?.cancel()
        syncCurrentTab()
        do {
            let url = try Self.recoverySnapshotURL(createFolder: true)
            try JSONEncoder().encode(currentRecoverySession()).write(to: url, options: .atomic)
        } catch {
            NSLog("Mirror could not preserve the editing session: %@", error.localizedDescription)
        }
    }

    private func scheduleRecoverySnapshot() {
        recoveryTask?.cancel()
        let session = currentRecoverySession()
        recoveryTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                let url = try Self.recoverySnapshotURL(createFolder: true)
                try JSONEncoder().encode(session).write(to: url, options: .atomic)
            } catch { }
        }
    }

    private func currentRecoverySession() -> RecoverySession {
        var snapshots = openTabs
        if let id = activeTabID, let index = snapshots.firstIndex(where: { $0.id == id }) {
            snapshots[index] = snapshotCurrentTab(id: id)
        }
        return RecoverySession(version: 2, tabs: snapshots, activeTabID: activeTabID, savedAt: Date())
    }

    private func scheduleDocumentAnalysis() {
        documentAnalysisTask?.cancel()
        let snapshot = text
        let isMarkdown = documentFormat.isMarkdown
        if snapshot.utf16.count < 40_000 {
            headings = isMarkdown ? Self.extractHeadings(from: snapshot) : []
            stats = WritingStats(text: snapshot)
            return
        }
        documentAnalysisTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(110))
            guard !Task.isCancelled else { return }
            let analysis = await Task.detached(priority: .utility) {
                (isMarkdown ? Self.extractHeadings(from: snapshot) : [], WritingStats(text: snapshot))
            }.value
            guard !Task.isCancelled, self?.text == snapshot else { return }
            self?.headings = analysis.0
            self?.stats = analysis.1
        }
    }

    private func restoreRecoverySessionIfAvailable() -> Bool {
        guard let url = try? Self.recoverySnapshotURL(createFolder: false),
              let data = try? Data(contentsOf: url) else { return false }
        let decoder = JSONDecoder()
        if let session = try? decoder.decode(RecoverySession.self, from: data) {
            var restored: [OpenDocumentTab] = []
            for var tab in session.tabs {
                if let previewPath = tab.previewPath {
                    guard FileManager.default.fileExists(atPath: previewPath) else { continue }
                } else if let filePath = tab.filePath, !tab.isDirty,
                          FileManager.default.fileExists(atPath: filePath),
                          let decoded = try? Self.readTextFile(URL(fileURLWithPath: filePath)) {
                    tab.text = decoded.text
                    tab.encodingRawValue = decoded.encoding.rawValue
                    tab.lineEndingRawValue = decoded.lineEnding.rawValue
                    tab.fileRevision = decoded.revision
                } else if tab.filePath == nil, tab.text.isEmpty {
                    continue
                }
                restored.append(tab)
            }
            guard !restored.isEmpty else { return false }
            openTabs = restored
            let selected = restored.first(where: { $0.id == session.activeTabID }) ?? restored[0]
            loadTab(selected)
            flash(restored.contains(where: \.isDirty)
                ? "Recovered \(restored.count) tabs with unsaved changes"
                : "Restored \(restored.count) tabs")
            return true
        }
        guard let snapshot = try? decoder.decode(RecoverySnapshot.self, from: data), !snapshot.text.isEmpty else { return false }
        let legacy = OpenDocumentTab(id: UUID(), text: snapshot.text, filePath: snapshot.filePath,
                                     previewPath: nil, encodingRawValue: snapshot.encodingRawValue,
                                     lineEndingRawValue: DocumentLineEnding.lf.rawValue,
                                     fileRevision: nil,
                                     isDirty: true, selectionLocation: 0, selectionLength: 0, readerMode: false)
        openTabs = [legacy]
        loadTab(legacy)
        flash("Recovered an unsaved draft")
        return true
    }

    private nonisolated static func recoverySnapshotURL(createFolder: Bool) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil,
                                                  create: createFolder)
        let folder = support.appendingPathComponent("Mirror/Recovery", isDirectory: true)
        if createFolder { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        return folder.appendingPathComponent("current-draft.json")
    }

    private func confirmDiscardIfNeeded() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(title)?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(); return !isDirty
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func flash(_ message: String) {
        notice = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if self?.notice == message { self?.notice = nil }
        }
    }

    private func showError(_ message: String, _ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private func showWorkspaceError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Workspace operation failed"
        alert.informativeText = message
        alert.runModal()
    }

    private func applyOpenedText(_ value: String,
                                 encoding: String.Encoding,
                                 lineEnding: DocumentLineEnding,
                                 revision: FileRevision?,
                                 url: URL) {
        guard prepareCurrentTabForSwitch() else { return }
        let tab = OpenDocumentTab(id: UUID(), text: value, filePath: url.standardizedFileURL.path,
                                  previewPath: nil, encodingRawValue: encoding.rawValue,
                                  lineEndingRawValue: lineEnding.rawValue, fileRevision: revision, isDirty: false,
                                  selectionLocation: 0, selectionLength: 0, readerMode: false)
        openTabs.append(tab)
        loadTab(tab)
        recordRecent(url)
        flash("Opened \(url.lastPathComponent)")
        scheduleRecoverySnapshot()
    }

    private nonisolated static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
    private nonisolated static let imageExtensions: Set<String> = [
        "avif", "bmp", "gif", "heic", "heif", "ico", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"
    ]
    private nonisolated static let knownBinaryExtensions: Set<String> = [
        "7z", "a", "app", "avi", "bin", "class", "dmg", "doc", "docx", "dylib", "eot", "epub", "exe",
        "gz", "jar", "key", "m4a", "m4v", "mov", "mp3", "mp4", "numbers", "o", "otf", "pages", "pdf",
        "pkg", "ppt", "pptx", "rar", "sqlite", "sqlite3", "tar", "ttf", "wav", "webm", "woff", "woff2",
        "xls", "xlsx", "zip"
    ]
    private nonisolated static let textExtensions: Set<String> = [
        "bash", "c", "cc", "cfg", "clj", "conf", "cpp", "cs", "css", "csv", "dart", "env", "fish", "go",
        "graphql", "h", "hpp", "htm", "html", "ini", "java", "js", "json", "jsonl", "jsx", "kt", "kts",
        "less", "log", "lua", "m", "mm", "php", "plist", "properties", "proto", "py", "r", "rb", "rs",
        "sass", "scala", "scss", "sh", "sql", "swift", "tex", "text", "toml", "ts", "tsv", "tsx", "txt",
        "vue", "xml", "yaml", "yml", "zsh"
    ]
    private nonisolated static let textFileNames: Set<String> = [
        "dockerfile", "gemfile", "license", "makefile", "podfile", "readme", "rakefile"
    ]

    private nonisolated static func isImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return true }
        return UTType(filenameExtension: ext)?.conforms(to: .image) == true
    }

    private nonisolated static func isKnownBinary(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if knownBinaryExtensions.contains(ext) { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .archive) || type.conforms(to: .audio) || type.conforms(to: .video) || type.conforms(to: .pdf)
    }

    private nonisolated static func isLikelyEditableText(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if markdownExtensions.contains(ext) || textExtensions.contains(ext) { return true }
        if textFileNames.contains(url.lastPathComponent.lowercased()) { return true }
        return UTType(filenameExtension: ext)?.conforms(to: .text) == true
    }

    private nonisolated static func editableFormat(for url: URL) -> EditableDocumentFormat {
        let ext = url.pathExtension.lowercased()
        if markdownExtensions.contains(ext) { return .markdown }
        let aliases = [
            "bash": "shell", "zsh": "shell", "fish": "shell", "sh": "shell",
            "c": "cpp", "cc": "cpp", "h": "cpp", "hpp": "cpp", "m": "objective-c", "mm": "objective-cpp",
            "cs": "csharp", "htm": "html", "js": "javascript", "jsx": "javascript", "jsonl": "json",
            "kt": "kotlin", "kts": "kotlin", "py": "python", "ts": "typescript",
            "plist": "xml", "properties": "ini", "rb": "ruby", "rs": "rust",
            "tsx": "typescript", "vue": "html", "yml": "yaml"
        ]
        if ext.isEmpty {
            let name = url.lastPathComponent.lowercased()
            if name == "dockerfile" { return .text(language: "dockerfile") }
            if name == "makefile" { return .text(language: "makefile") }
            return .text(language: nil)
        }
        let plain: Set<String> = ["csv", "log", "text", "tsv", "txt"]
        return .text(language: plain.contains(ext) ? nil : (aliases[ext] ?? ext))
    }

    private struct DecodedTextFile: Sendable {
        let text: String
        let encoding: String.Encoding
        let lineEnding: DocumentLineEnding
        let revision: FileRevision?
    }

    private nonisolated static func readTextFile(_ url: URL) throws -> DecodedTextFile {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        if data.isEmpty {
            return DecodedTextFile(text: "", encoding: .utf8, lineEnding: .lf,
                                   revision: fileRevision(at: url, contentFingerprint: contentFingerprint(data)))
        }
        let bytes = [UInt8](data.prefix(16_384))
        let hasUTF16BOM = bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF])
        if !hasUTF16BOM {
            let controls = bytes.filter { $0 == 0 || ($0 < 0x09) || ($0 > 0x0D && $0 < 0x20) }.count
            if bytes.contains(0) || controls > max(8, bytes.count / 20) {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        let encodings: [String.Encoding] = hasUTF16BOM
            ? [.utf16, .utf16LittleEndian, .utf16BigEndian]
            : [.utf8, gb18030, .windowsCP1252, .isoLatin1, .macOSRoman]
        for encoding in encodings {
            if let value = String(data: data, encoding: encoding) {
                let crlfCount = max(0, value.components(separatedBy: "\r\n").count - 1)
                let lfCount = value.reduce(into: 0) { if $1 == "\n" { $0 += 1 } } - crlfCount
                let crCount = value.reduce(into: 0) { if $1 == "\r" { $0 += 1 } } - crlfCount
                let ending: DocumentLineEnding
                if crlfCount > 0, crlfCount >= lfCount, crlfCount >= crCount {
                    ending = .crlf
                } else if crCount > lfCount {
                    ending = .cr
                } else {
                    ending = .lf
                }
                let normalized = value.replacingOccurrences(of: "\r\n", with: "\n")
                    .replacingOccurrences(of: "\r", with: "\n")
                return DecodedTextFile(text: normalized, encoding: encoding, lineEnding: ending,
                                       revision: fileRevision(at: url, contentFingerprint: contentFingerprint(data)))
            }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }

    private func serializedText(_ value: String) -> String {
        switch lineEnding {
        case .lf: return value
        case .crlf: return value.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr: return value.replacingOccurrences(of: "\n", with: "\r")
        }
    }

    private nonisolated static func fileRevision(at url: URL, contentFingerprint: UInt64? = nil) -> FileRevision? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              let size = (attributes[.size] as? NSNumber)?.intValue else { return nil }
        return FileRevision(modificationTime: date.timeIntervalSince1970,
                            fileSize: size,
                            contentFingerprint: contentFingerprint)
    }

    private nonisolated static func fileRevisionAfterWrite(at url: URL,
                                                           text: String,
                                                           encoding: String.Encoding) -> FileRevision? {
        if let data = text.data(using: encoding) {
            return fileRevision(at: url, contentFingerprint: contentFingerprint(data))
        }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return fileRevision(at: url) }
        return fileRevision(at: url, contentFingerprint: contentFingerprint(data))
    }

    private nonisolated static func reconciledFileRevision(at url: URL, expected: FileRevision) -> FileRevision? {
        guard let current = fileRevision(at: url) else { return nil }
        if current.modificationTime == expected.modificationTime,
           current.fileSize == expected.fileSize {
            return expected
        }
        guard let expectedFingerprint = expected.contentFingerprint,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              contentFingerprint(data) == expectedFingerprint else { return nil }
        return FileRevision(modificationTime: current.modificationTime,
                            fileSize: current.fileSize,
                            contentFingerprint: expectedFingerprint)
    }

    private nonisolated static func contentFingerprint(_ data: Data) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private func promptForName(title: String, message: String, defaultValue: String, actionTitle: String) -> String? {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = defaultValue
        field.selectText(nil)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.accessoryView = field
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func validatedWorkspaceName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".", name != "..",
              !name.hasPrefix("."),
              !name.contains("/"), !name.contains(":"), !name.contains("\0") else {
            showWorkspaceError("Use a visible name without slashes, colons, or leading dots.")
            return nil
        }
        return name
    }

    private func availableName(base: String, extension fileExtension: String?, in directory: URL) -> String {
        func candidate(_ suffix: Int?) -> String {
            let stem = suffix.map { "\(base) \($0)" } ?? base
            return fileExtension.map { "\(stem).\($0)" } ?? stem
        }
        var index: Int? = nil
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate(index)).path) {
            index = (index ?? 1) + 1
        }
        return candidate(index)
    }

    private func normalizedTransferSources(_ urls: [URL]) -> [URL] {
        let unique = Dictionary(grouping: urls.map(\.standardizedFileURL), by: \.path)
            .compactMap(\.value.first)
            .sorted { $0.path.count < $1.path.count }
        var result: [URL] = []
        for url in unique where !result.contains(where: { isSameOrDescendant(url, of: $0) }) {
            result.append(url)
        }
        return result
    }

    private func availableCopyDestination(for source: URL, in directory: URL, reservedPaths: inout Set<String>) -> URL {
        let original = directory.appendingPathComponent(source.lastPathComponent).standardizedFileURL
        if !FileManager.default.fileExists(atPath: original.path), reservedPaths.insert(original.path).inserted {
            return original
        }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory)
        let fileExtension = isDirectory.boolValue ? "" : source.pathExtension
        let stem = isDirectory.boolValue || fileExtension.isEmpty
            ? source.lastPathComponent
            : source.deletingPathExtension().lastPathComponent
        var index = 1
        while true {
            let suffix = index == 1 ? " copy" : " copy \(index)"
            let name = fileExtension.isEmpty ? stem + suffix : stem + suffix + "." + fileExtension
            let candidate = directory.appendingPathComponent(name).standardizedFileURL
            if !FileManager.default.fileExists(atPath: candidate.path), reservedPaths.insert(candidate.path).inserted {
                return candidate
            }
            index += 1
        }
    }

    private func isWorkspaceLocation(_ url: URL) -> Bool {
        guard let root = workspaceURL?.standardizedFileURL else { return false }
        let path = url.standardizedFileURL.path
        return path == root.path || path.hasPrefix(root.path + "/")
    }

    private func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let ancestorPath = ancestor.standardizedFileURL.path
        return candidatePath == ancestorPath || candidatePath.hasPrefix(ancestorPath + "/")
    }

    private func remapReferences(from source: URL, to destination: URL) {
        let historySource = source.standardizedFileURL
        let historyDestination = destination.standardizedFileURL
        Task.detached(priority: .utility) {
            Self.migrateDocumentHistoryReferences(from: historySource, to: historyDestination)
        }
        func remap(_ candidate: URL?) -> URL? {
            guard let candidate else { return nil }
            let candidatePath = candidate.standardizedFileURL.path
            let sourcePath = source.standardizedFileURL.path
            guard candidatePath == sourcePath || candidatePath.hasPrefix(sourcePath + "/") else { return candidate }
            let relative = String(candidatePath.dropFirst(sourcePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return relative.isEmpty ? destination : destination.appendingPathComponent(relative)
        }
        fileURL = remap(fileURL)
        previewFileURL = remap(previewFileURL)
        for index in openTabs.indices {
            if let path = openTabs[index].filePath,
               let mapped = remap(URL(fileURLWithPath: path)) {
                openTabs[index].filePath = mapped.path
            }
            if let path = openTabs[index].previewPath,
               let mapped = remap(URL(fileURLWithPath: path)) {
                openTabs[index].previewPath = mapped.path
            }
        }
        if let fileURL {
            documentFormat = Self.editableFormat(for: fileURL)
            headings = documentFormat.isMarkdown ? Self.extractHeadings(from: text) : []
        }
        var seen = Set<String>()
        recentFiles = recentFiles.compactMap { remap($0) }.filter { seen.insert($0.path).inserted }
        persistRecentFiles()
        syncCurrentTab()
        scheduleRecoverySnapshot()
    }

    private func recordRecent(_ url: URL) {
        let normalized = url.standardizedFileURL
        recentFiles.removeAll { $0.standardizedFileURL == normalized }
        recentFiles.insert(normalized, at: 0)
        if recentFiles.count > 10 { recentFiles.removeLast(recentFiles.count - 10) }
        persistRecentFiles()
    }

    private func persistRecentFiles() {
        UserDefaults.standard.set(recentFiles.map(\.path), forKey: "MirrorRecentFiles")
    }

    private static func loadRecentFiles() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: "MirrorRecentFiles") ?? []
        return paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private nonisolated static func enumerateWorkspace(in root: URL) -> WorkspaceSnapshot {
        var allFiles: [URL] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey]

        func nodes(in directory: URL) -> [WorkspaceNode] {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { return [] }

            return contents.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: keys), values.isHidden != true else { return nil }
                if values.isDirectory == true && values.isPackage != true && values.isSymbolicLink != true {
                    let children = nodes(in: url)
                    return WorkspaceNode(url: url, isDirectory: true, children: children.isEmpty ? nil : children)
                }
                guard values.isRegularFile == true || values.isPackage == true else { return nil }
                allFiles.append(url)
                return WorkspaceNode(url: url, isDirectory: false, children: nil)
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        }

        func markdownNode(_ node: WorkspaceNode) -> WorkspaceNode? {
            if !node.isDirectory {
                return ["md", "markdown"].contains(node.url.pathExtension.lowercased()) ? node : nil
            }
            let children = (node.children ?? []).compactMap(markdownNode)
            guard !children.isEmpty else { return nil }
            return WorkspaceNode(url: node.url, isDirectory: true, children: children)
        }

        let tree = nodes(in: root)
        let markdownTree = tree.compactMap(markdownNode)
        let markdownCount = allFiles.lazy.filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) }.count
        return WorkspaceSnapshot(files: allFiles, tree: tree, markdownTree: markdownTree, markdownCount: markdownCount)
    }

    private nonisolated static func findWorkspaceMatches(query: String,
                                                         files: [URL],
                                                         caseSensitive: Bool,
                                                         regularExpression: Bool) -> [WorkspaceSearchResult] {
        let maximumResults = 1_000
        let maximumFileSize = 12 * 1_024 * 1_024
        let regex = regularExpression
            ? try? NSRegularExpression(pattern: query, options: caseSensitive ? [] : [.caseInsensitive])
            : nil
        var results: [WorkspaceSearchResult] = []
        for url in files {
            if Task.isCancelled || results.count >= maximumResults { break }
            if isImage(url) || isKnownBinary(url) { continue }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumFileSize { continue }
            guard let decoded = try? readTextFile(url) else { continue }
            for (lineIndex, line) in decoded.text.components(separatedBy: .newlines).enumerated() {
                if Task.isCancelled || results.count >= maximumResults { break }
                let source = line as NSString
                let fullRange = NSRange(location: 0, length: source.length)
                let matches: [NSRange]
                if let regex {
                    matches = regex.matches(in: line, range: fullRange).map(\.range)
                } else {
                    var found: [NSRange] = []
                    var remaining = fullRange
                    let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
                    while remaining.length > 0 {
                        let match = source.range(of: query, options: options, range: remaining)
                        guard match.location != NSNotFound else { break }
                        found.append(match)
                        let next = match.location + max(1, match.length)
                        remaining = NSRange(location: next, length: max(0, source.length - next))
                    }
                    matches = found
                }
                guard !matches.isEmpty else { continue }
                let preview = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\t", with: "    ")
                for match in matches.prefix(30) where results.count < maximumResults {
                    results.append(WorkspaceSearchResult(url: url,
                                                         line: lineIndex,
                                                         column: match.location,
                                                         preview: String(preview.prefix(300)),
                                                         matchLength: match.length))
                }
            }
        }
        return results
    }

    static let welcomeText = """
    # Welcome to Mirror

    A quiet place for clear thinking.

    ## Write naturally

    Mirror keeps Markdown close, while the live canvas shows the shape of your document as you type. Try **bold**, _emphasis_, `inline code`, or a [link](https://example.com).

    > Good writing begins with a little room to breathe.

    ## Keep your flow

    - [x] Open or drop a Markdown file
    - [x] Navigate from the outline
    - [ ] Turn the next thought into words

    ```swift
    let idea = "small, focused, useful"
    print(idea)
    ```

    ---

    Use **⌘S** to save, **⇧⌘J** for focus mode, and **⌥⌘2** to toggle the preview.
    """
}

enum EditorCommand: Equatable {
    case insert(String)
    case insertAtSelection(String)
    case wrap(left: String, right: String, placeholder: String)
    case select(NSRange)
    case showFind
    case showReplace
}

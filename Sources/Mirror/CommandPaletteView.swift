import SwiftUI

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let category: String
    let icon: String
    let shortcut: String?
    let keywords: String
    let isEnabled: Bool
    let action: () -> Void
}

struct CommandPaletteView: View {
    @EnvironmentObject private var document: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @State private var query = ""
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool

    private var canEdit: Bool { document.previewFileURL == nil && !document.readerMode }
    private var canFormat: Bool { canEdit && document.isMarkdownDocument }

    private var commands: [PaletteCommand] {
        fileCommands + navigationCommands + viewCommands + formatCommands + exportCommands + appearanceCommands
    }

    private var fileCommands: [PaletteCommand] {
        [
            command("file.new", "New Document", "File", "doc.badge.plus", "⌘N", "new tab") { document.newDocument() },
            command("file.open", "Open File…", "File", "folder", "⌘O", "open document") { document.openDocument() },
            command("file.folder", document.workspaceURL == nil ? "Open Folder…" : "Change Folder…", "File", "folder.badge.plus", nil, "workspace project directory") { document.chooseWorkspaceFolder() },
            command("file.quick", "Quick Open…", "File", "doc.text.magnifyingglass", "⌘P", "file name path") { document.showQuickOpen = true },
            command("file.search", "Search in Folder…", "Search", "text.magnifyingglass", "⇧⌘F", "workspace full text regex") { document.showWorkspaceSearch = true },
            command("file.save", "Save", "File", "square.and.arrow.down", "⌘S", "write document", enabled: document.previewFileURL == nil) { document.save() },
            command("file.saveAs", "Save As…", "File", "square.and.arrow.down.on.square", "⇧⌘S", "duplicate copy", enabled: document.previewFileURL == nil) { document.saveAs() },
            command("search.find", "Find in Document…", "Search", "magnifyingglass", "⌘F", "search current", enabled: canEdit) { document.showFind() },
            command("search.replace", "Find and Replace…", "Search", "arrow.triangle.2.circlepath", "⌥⌘F", "replace current", enabled: canEdit) { document.showReplace() }
        ]
    }

    private var navigationCommands: [PaletteCommand] {
        [
            command("navigate.line", "Go to Line…", "Navigate", "number", "⌃G", "jump line", enabled: canEdit) { document.goToLine() },
            command("navigate.history", "Document History…", "Navigate", "clock.arrow.circlepath", "⇧⌘H", "versions restore backup", enabled: document.fileURL != nil && document.previewFileURL == nil) { document.showDocumentHistory = true },
            command("navigate.previous", "Previous Tab", "Navigate", "chevron.left", "⇧⌘[", "tab", enabled: document.openTabs.count > 1) { document.selectNextTab(offset: -1) },
            command("navigate.next", "Next Tab", "Navigate", "chevron.right", "⇧⌘]", "tab", enabled: document.openTabs.count > 1) { document.selectNextTab(offset: 1) },
            command("navigate.close", "Close Tab", "Navigate", "xmark", "⌘W", "tab") {
                if let id = document.activeTabID { document.closeTab(id) }
            }
        ]
    }

    private var viewCommands: [PaletteCommand] {
        [
            command("view.navigation", "Toggle Navigation", "View", "sidebar.left", "⌥⌘1", "sidebar panels") { document.toggleNavigation() },
            command("view.library", "Toggle File Library", "View", "folder", nil, "sidebar workspace recent") {
                document.showFileLibrary.toggle(); document.showSidebar = true
            },
            command("view.outline", "Toggle Document Outline", "View", "list.bullet.indent", nil, "headings structure") {
                document.showOutline.toggle(); document.showSidebar = true
            },
            command("view.preview", "Toggle Preview", "View", "rectangle.righthalf.inset.filled", "⌥⌘2", "render split", enabled: document.isMarkdownDocument && document.previewFileURL == nil && !document.readerMode) { document.showPreview.toggle() },
            command("view.focus", "Toggle Focus Mode", "View", "arrow.up.left.and.arrow.down.right", "⇧⌘J", "zen distraction free", enabled: document.previewFileURL == nil) { document.focusMode.toggle() },
            command("view.reader", "Toggle Reader Mode", "View", "book.pages", "⇧⌘R", "formatted only", enabled: document.isMarkdownDocument && document.previewFileURL == nil) { document.toggleReaderMode() }
        ]
    }

    private var formatCommands: [PaletteCommand] {
        [
            command("format.heading", "Insert Heading", "Format", "textformat.size.larger", "⌘2", "markdown h2", enabled: canFormat) { document.insert(prefix: "## ") },
            command("format.bold", "Bold", "Format", "bold", "⌘B", "markdown strong", enabled: canFormat) { document.wrapSelection(left: "**", right: "**", placeholder: "bold text") },
            command("format.italic", "Italic", "Format", "italic", "⌘I", "markdown emphasis", enabled: canFormat) { document.wrapSelection(left: "_", right: "_", placeholder: "italic text") },
            command("format.link", "Insert Link", "Format", "link", "⌘K", "markdown url", enabled: canFormat) { document.wrapSelection(left: "[", right: "](https://)", placeholder: "link text") },
            command("format.image", "Insert Image…", "Format", "photo.badge.plus", "⌥⌘I", "attachment asset paste drag", enabled: canFormat) { document.chooseImagesToInsert() },
            command("format.code", "Inline Code", "Format", "chevron.left.forwardslash.chevron.right", "⇧⌘K", "markdown code", enabled: canFormat) { document.wrapSelection(left: "`", right: "`", placeholder: "code") },
            command("format.bullets", "Bulleted List", "Format", "list.bullet", nil, "unordered markdown", enabled: canFormat) { document.insert(prefix: "- ") },
            command("format.numbered", "Numbered List", "Format", "list.number", nil, "ordered markdown", enabled: canFormat) { document.insert(prefix: "1. ") },
            command("format.quote", "Block Quote", "Format", "text.quote", nil, "markdown", enabled: canFormat) { document.insert(prefix: "> ") },
            command("format.table", "Insert Table…", "Format", "tablecells", nil, "markdown gfm rows columns alignment", enabled: canFormat) { document.showTableBuilder = true },
            command("format.math", "Display Math", "Format", "function", nil, "latex katex equation", enabled: canFormat) { document.wrapSelection(left: "$$\n", right: "\n$$", placeholder: "\\int_0^1 x^2\\,dx") },
            command("format.mermaid", "Mermaid Diagram Block", "Format", "point.3.connected.trianglepath.dotted", nil, "sequence flowchart diagram", enabled: canFormat) { document.wrapSelection(left: "```mermaid\n", right: "\n```", placeholder: "flowchart LR\n    A --> B") }
        ]
    }

    private var exportCommands: [PaletteCommand] {
        [
            command("export.html", "Export HTML…", "Export", "globe", "⇧⌘E", "web rendered", enabled: document.isMarkdownDocument && document.previewFileURL == nil && !document.isExportingDocument) { document.exportHTML() },
            command("export.pdf", "Export PDF…", "Export", "doc.fill", "⌥⌘P", "print rendered", enabled: document.isMarkdownDocument && document.previewFileURL == nil && !document.isExportingDocument) { document.exportPDF() },
            command("export.print", "Print…", "Export", "printer", nil, "paper", enabled: document.isMarkdownDocument && document.previewFileURL == nil && !document.isExportingDocument) { document.printDocument() }
        ]
    }

    private var appearanceCommands: [PaletteCommand] {
        var items = [
            command("appearance.settings", "Theme & Typography Settings…", "Appearance", "paintpalette", "⌘,", "font skin editor import") { openSettings() }
        ]
        items.append(contentsOf: document.availableThemes.map { theme in
            command("theme.\(theme.id)", "Use Theme: \(theme.name)", "Appearance", "paintpalette.fill", nil,
                    "skin \(theme.isDark ? "dark" : "light")") { document.selectTheme(theme) }
        })
        return items
    }

    private var filteredCommands: [PaletteCommand] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return commands }
        return commands.filter { item in
            let searchable = "\(item.title) \(item.category) \(item.keywords) \(item.shortcut ?? "")".lowercased()
            return terms.allSatisfy(searchable.contains)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command").foregroundStyle(document.theme.accent)
                TextField("Type a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($searchFocused)
                    .onSubmit { executeSelected() }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(16)

            Divider()

            if filteredCommands.isEmpty {
                ContentUnavailableView("No Matching Commands", systemImage: "command")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $selectedID) {
                        ForEach(filteredCommands) { item in
                            HStack(spacing: 10) {
                                Image(systemName: item.icon)
                                    .foregroundStyle(item.isEnabled ? document.theme.accent : .secondary)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(LocalizedStringKey(item.title)).font(.system(size: 12.5, weight: .medium))
                                    Text(LocalizedStringKey(item.category)).font(.system(size: 9.5)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let shortcut = item.shortcut {
                                    Text(shortcut).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 3)
                            .opacity(item.isEnabled ? 1 : 0.42)
                            .tag(item.id)
                            .id(item.id)
                            .onTapGesture { if item.isEnabled { execute(item) } }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: selectedID) { _, id in
                        if let id { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) } }
                    }
                }
            }

            Divider()
            HStack(spacing: 12) {
                Text("↑↓ Navigate")
                Text("↩ Run")
                Text("⌘⇧P Command Palette")
                Spacer()
                Text("\(filteredCommands.count) commands")
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .frame(width: 650, height: 500)
        .nativeDialog(theme: document.theme)
        .preferredColorScheme(document.theme.isDark ? .dark : .light)
        .onAppear {
            searchFocused = true
            selectedID = filteredCommands.first(where: \.isEnabled)?.id
        }
        .onChange(of: query) { _, _ in
            selectedID = filteredCommands.first(where: \.isEnabled)?.id
        }
    }

    private func command(_ id: String,
                         _ title: String,
                         _ category: String,
                         _ icon: String,
                         _ shortcut: String?,
                         _ keywords: String,
                         enabled: Bool = true,
                         action: @escaping () -> Void) -> PaletteCommand {
        PaletteCommand(id: id, title: title, category: category, icon: icon, shortcut: shortcut,
                       keywords: keywords, isEnabled: enabled, action: action)
    }

    private func moveSelection(_ offset: Int) {
        let enabled = filteredCommands.filter(\.isEnabled)
        guard !enabled.isEmpty else { selectedID = nil; return }
        let index = selectedID.flatMap { id in enabled.firstIndex(where: { $0.id == id }) } ?? (offset > 0 ? -1 : 0)
        selectedID = enabled[(index + offset + enabled.count) % enabled.count].id
    }

    private func executeSelected() {
        guard let item = filteredCommands.first(where: { $0.id == selectedID && $0.isEnabled })
                ?? filteredCommands.first(where: \.isEnabled) else { return }
        execute(item)
    }

    private func execute(_ item: PaletteCommand) {
        guard item.isEnabled else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item.action)
    }
}

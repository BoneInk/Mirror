import SwiftUI

@main
struct MirrorApp: App {
    @StateObject private var document = DocumentStore()
    @StateObject private var language = AppLanguageStore()
    @StateObject private var updates = SoftwareUpdateStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showUpdates = false

    var body: some Scene {
        Window("Mirror", id: "main") {
            LocalizedContentRoot(document: document, language: language)
                .frame(minWidth: 1120, minHeight: 620)
                .task { await updates.check(automatic: true) }
                .onReceive(Timer.publish(every: 3600, on: .main, in: .common).autoconnect()) { _ in
                    Task { await updates.check(automatic: true) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await updates.check(automatic: true) } }
                }
                .sheet(isPresented: $showUpdates) {
                    SoftwareUpdateView(updates: updates)
                        .environmentObject(document).environment(\.locale, language.locale)
                        .padding(24).frame(width: 620, height: 410)
                        .nativeDialog(theme: document.theme)
                        .preferredColorScheme(document.theme.isDark ? .dark : .light)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                Button(language.text("Check for Updates…")) {
                    showUpdates = true
                    Task { await updates.check() }
                }
                .disabled(updates.busy)
            }
            CommandGroup(replacing: .newItem) {
                Button(language.text("New Document")) { document.newDocument() }
                    .keyboardShortcut("n")
                Button(language.text("Open…")) { document.openDocument() }
                    .keyboardShortcut("o")
                Divider()
                Button(language.text("Save")) { document.save() }
                    .keyboardShortcut("s")
                Button(language.text("Save As…")) { document.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button(language.text("Export HTML…")) { document.exportHTML() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.isExportingDocument)
                Button(language.text("Export PDF…")) { document.exportPDF() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.isExportingDocument)
                Button(language.text("Print…")) { document.printDocument() }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.isExportingDocument)
            }
            CommandMenu(language.text("View")) {
                Button(language.text("Toggle Navigation")) { document.toggleNavigation() }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button(language.text("Toggle File Library")) {
                    if document.showSidebar && document.showFileLibrary && !document.showOutline {
                        document.showFileLibrary = false
                    } else {
                        document.showSidebar = true
                        document.showFileLibrary = true
                        document.showOutline = false
                    }
                }
                Button(language.text("Toggle Document Outline")) {
                    if document.showSidebar && document.showOutline {
                        document.showOutline = false
                    } else {
                        document.showSidebar = true
                        document.showOutline = true
                        document.showFileLibrary = false
                    }
                }
                Button(language.text("Toggle Preview")) { document.showPreview.toggle() }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button(language.text("Focus Mode")) { document.focusMode.toggle() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Button(language.text("Reader Mode")) { document.toggleReaderMode() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu(language.text("Navigate")) {
                Button(language.text("Command Palette…")) { document.showCommandPalette = true }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button(language.text("Quick Open…")) { document.showQuickOpen = true }
                    .keyboardShortcut("p")
                Button(language.text("Search in Folder…")) { document.showWorkspaceSearch = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button(language.text("Find in Document…")) { document.showFind() }
                    .keyboardShortcut("f")
                    .disabled(document.previewFileURL != nil || document.readerMode)
                Button(language.text("Find and Replace…")) { document.showReplace() }
                    .keyboardShortcut("f", modifiers: [.command, .option])
                    .disabled(document.previewFileURL != nil || document.readerMode)
                Button(language.text("Go to Line…")) { document.goToLine() }
                    .keyboardShortcut("g", modifiers: [.control])
                    .disabled(document.previewFileURL != nil || document.readerMode)
                Button(language.text("Document History…")) { document.showDocumentHistory = true }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(document.fileURL == nil || document.previewFileURL != nil)
                Divider()
                Button(language.text("Previous Tab")) { document.selectNextTab(offset: -1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                    .disabled(document.openTabs.count < 2)
                Button(language.text("Next Tab")) { document.selectNextTab(offset: 1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                    .disabled(document.openTabs.count < 2)
                Button(language.text("Close Tab")) {
                    if let id = document.activeTabID { document.closeTab(id) }
                }
                .keyboardShortcut("w")
            }
            CommandMenu(language.text("Format")) {
                Button(language.text("Heading")) { document.insert(prefix: "## ") }
                    .keyboardShortcut("2", modifiers: [.command])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Bold")) { document.wrapSelection(left: "**", right: "**", placeholder: "bold text") }
                    .keyboardShortcut("b")
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Italic")) { document.wrapSelection(left: "_", right: "_", placeholder: "italic text") }
                    .keyboardShortcut("i")
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Inline Code")) { document.wrapSelection(left: "`", right: "`", placeholder: "code") }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Strikethrough")) { document.wrapSelection(left: "~~", right: "~~", placeholder: "struck text") }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Link")) { document.wrapSelection(left: "[", right: "](https://)", placeholder: "link text") }
                    .keyboardShortcut("k")
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Insert Image…")) { document.chooseImagesToInsert() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.readerMode)
                Divider()
                Button(language.text("Bulleted List")) { document.insert(prefix: "- ") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Numbered List")) { document.insert(prefix: "1. ") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Block Quote")) { document.insert(prefix: "> ") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Table…")) { document.showTableBuilder = true }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil || document.readerMode)
                Divider()
                Button(language.text("Inline Math")) { document.wrapSelection(left: "$", right: "$", placeholder: "E = mc^2") }
                    .keyboardShortcut("m", modifiers: [.command, .control])
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Display Math")) { document.wrapSelection(left: "$$\n", right: "\n$$", placeholder: "\\int_0^1 x^2\\,dx") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
                Button(language.text("Fenced Code Block")) { document.wrapSelection(left: "```text\n", right: "\n```", placeholder: "code") }
                    .disabled(!document.isMarkdownDocument || document.previewFileURL != nil)
            }
            CommandMenu(language.text("Appearance")) {
                ForEach(document.availableThemes) { theme in
                    Button {
                        document.selectTheme(theme)
                    } label: {
                        if document.theme.id == theme.id {
                            Label(theme.name, systemImage: "checkmark")
                        } else {
                            Text(theme.name)
                        }
                    }
                }
                Divider()
                SettingsLink { Text(language.text("Theme & Typography Settings…")) }
            }
            CommandMenu("语言 / Language") {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        document.persistForApplicationTermination()
                        language.selectAndRelaunch(option)
                    } label: {
                        if language.selection == option {
                            Label(option.menuTitle, systemImage: "checkmark")
                        } else {
                            Text(option.menuTitle)
                        }
                    }
                }
            }
        }

        Settings {
            LocalizedSettingsRoot(document: document, language: language, updates: updates)
        }
    }
}

private struct LocalizedContentRoot: View {
    @ObservedObject var document: DocumentStore
    @ObservedObject var language: AppLanguageStore

    var body: some View {
        ContentView()
            .environmentObject(document)
            .environment(\.locale, language.locale)
            .id(language.selection.rawValue)
    }
}

private struct LocalizedSettingsRoot: View {
    @ObservedObject var document: DocumentStore
    @ObservedObject var language: AppLanguageStore
    @ObservedObject var updates: SoftwareUpdateStore

    var body: some View {
        AppearanceSettingsView()
            .environmentObject(updates)
            .environmentObject(document)
            .environment(\.locale, language.locale)
            .id(language.selection.rawValue)
    }
}

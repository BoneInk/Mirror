import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        TabView {
            AgentSettingsView()
                .tabItem { Label("智能体", systemImage: "sparkles") }
            CodexMemorySettingsView()
                .tabItem { Label("气泡记忆", systemImage: "bubble.left.and.bubble.right") }
            ThemeSettingsView()
                .tabItem { Label("Themes", systemImage: "paintpalette") }
            TypographySettingsView()
                .tabItem { Label("Typography", systemImage: "textformat") }
            EditorBehaviorSettingsView()
                .tabItem { Label("Editor", systemImage: "slider.horizontal.3") }
        }
        .padding(20)
        .frame(width: 720, height: 570)
        .nativeDialog(theme: document.theme)
        .preferredColorScheme(document.theme.isDark ? .dark : .light)
    }
}

private struct EditorBehaviorSettingsView: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Editor").font(.title2.bold())
                    Text("Tune the writing surface for prose, notes, and source code.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset") { document.resetEditorSettings() }
            }

            Form {
                Section("Writing surface") {
                    Toggle("Show line numbers", isOn: $document.editorSettings.showLineNumbers)
                    Toggle("Highlight current line", isOn: $document.editorSettings.highlightCurrentLine)
                    Toggle("Check spelling in Markdown", isOn: $document.editorSettings.checkSpelling)
                    Toggle("Wrap long lines", isOn: $document.editorSettings.wordWrap)
                    Toggle("Typewriter mode keeps the insertion point centered", isOn: $document.editorSettings.typewriterMode)
                    Toggle("Preserve single line breaks in preview and exports",
                           isOn: $document.editorSettings.preserveSingleLineBreaks)
                    Toggle("Automatically close brackets and quotes", isOn: $document.editorSettings.autoPairDelimiters)
                    Picker("Source and preview scroll sync", selection: $document.editorSettings.scrollSyncMode) {
                        ForEach(ScrollSyncMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.label)).tag(mode)
                        }
                    }
                }

                Section("Editing") {
                    Picker("Tab width", selection: $document.editorSettings.tabWidth) {
                        Text("2 spaces").tag(2)
                        Text("4 spaces").tag(4)
                        Text("8 spaces").tag(8)
                    }
                    Picker("Autosave delay", selection: $document.editorSettings.autosaveDelay) {
                        Text("0.5 seconds").tag(0.5)
                        Text("1.2 seconds").tag(1.2)
                        Text("2 seconds").tag(2.0)
                        Text("5 seconds").tag(5.0)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Spacer()

            GroupBox {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "keyboard").font(.title2).foregroundStyle(document.theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Native editing commands stay available").font(.headline)
                        Text("Undo/redo, Find, spelling suggestions, copy/paste, text substitutions and macOS accessibility remain provided by the native text system.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            }
        }
    }
}

private struct ThemeSettingsView: View {
    @EnvironmentObject private var document: DocumentStore
    @State private var editingTheme: EditorTheme?

    private let columns = [GridItem(.adaptive(minimum: 132), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Themes").font(.title2.bold())
                    Text("Choose a built-in skin or create your own palette.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import…", systemImage: "square.and.arrow.down") { document.importThemes() }
                Button("Export…", systemImage: "square.and.arrow.up") { document.exportTheme(document.theme) }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    themeSection("Built-in", themes: EditorTheme.builtIns)
                    themeSection("Custom", themes: document.customThemes)

                    if document.customThemes.isEmpty {
                        ContentUnavailableView(
                            "No Custom Themes",
                            systemImage: "paintbrush",
                            description: Text("Duplicate any theme, then edit its colors and light/dark appearance.")
                        )
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()
            HStack {
                Text("Current: \(document.theme.name)")
                    .font(.callout.weight(.medium))
                Spacer()
                if !document.theme.isBuiltIn {
                    Button("Edit…") { editingTheme = document.theme }
                    Button("Delete", role: .destructive) { document.deleteCustomTheme(document.theme) }
                }
                Button("Duplicate & Customize…") {
                    editingTheme = document.duplicateTheme(document.theme)
                }
                .buttonStyle(NativeActionStyle(theme: document.theme, prominent: true))
            }
        }
        .sheet(item: $editingTheme) { theme in
            ThemeEditorView(theme: theme) { updated in
                document.saveCustomTheme(updated)
                editingTheme = nil
            } onCancel: {
                editingTheme = nil
            }
        }
    }

    @ViewBuilder
    private func themeSection(_ title: String, themes: [EditorTheme]) -> some View {
        if !themes.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text(LocalizedStringKey(title))
                    .textCase(.uppercase)
                    .font(.caption.bold()).tracking(1.1).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(themes) { theme in
                        ThemeCard(theme: theme, selected: theme.id == document.theme.id) {
                            document.selectTheme(theme)
                        }
                        .contextMenu {
                            Button("Use Theme") { document.selectTheme(theme) }
                            Button("Duplicate & Customize…") { editingTheme = document.duplicateTheme(theme) }
                            Button("Export…") { document.exportTheme(theme) }
                            if !theme.isBuiltIn {
                                Divider()
                                Button("Edit…") { editingTheme = theme }
                                Button("Delete", role: .destructive) { document.deleteCustomTheme(theme) }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: EditorTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 5) {
                    ForEach([theme.accentHex, theme.syntaxKeywordHex, theme.syntaxStringHex, theme.codeHex], id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 15, height: 15)
                    }
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: theme.accentHex)) }
                }
                Text(theme.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: theme.foregroundHex))
                    .lineLimit(1)
                Text(theme.isDark ? "Dark" : "Light")
                    .font(.caption2).foregroundStyle(Color(hex: theme.mutedHex))
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ContentSurface(theme: theme, radius: 10))
            .overlay {
                ContentShape(radius: 10)
                    .stroke(selected ? Color(hex: theme.accentHex) : .clear, lineWidth: selected ? 2 : 0)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeEditorView: View {
    @State var theme: EditorTheme
    let onSave: (EditorTheme) -> Void
    let onCancel: () -> Void

    private let colorFields: [(String, WritableKeyPath<EditorTheme, String>)] = [
        ("Background", \.backgroundHex), ("Text", \.foregroundHex), ("Secondary text", \.mutedHex),
        ("Borders", \.lineHex), ("Accent", \.accentHex), ("Code background", \.codeHex),
        ("Keyword", \.syntaxKeywordHex), ("String", \.syntaxStringHex), ("Comment", \.syntaxCommentHex),
        ("Number", \.syntaxNumberHex), ("Type", \.syntaxTypeHex), ("HTML tag", \.syntaxTagHex)
    ]
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Customize Theme").font(.title2.bold())
            HStack {
                TextField("Theme name", text: $theme.name)
                Toggle("Dark appearance", isOn: $theme.isDark)
                    .toggleStyle(.switch)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(colorFields, id: \.0) { label, keyPath in
                    ColorPicker(label, selection: colorBinding(keyPath), supportsOpacity: false)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview").font(.caption.bold()).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 7) {
                    Text("A calm place to write")
                        .font(.system(size: 19, weight: .bold))
                    Text("Readable text with a **clear** visual hierarchy.")
                    Text("let idea = \"Mirror\"")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color(hex: theme.syntaxKeywordHex))
                        .padding(7).background(Color(hex: theme.codeHex), in: RoundedRectangle(cornerRadius: 5))
                }
                .foregroundStyle(Color(hex: theme.foregroundHex))
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(ContentSurface(theme: theme, radius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color(hex: theme.lineHex)) }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save Theme") { onSave(theme) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 540)
        .nativeDialog(theme: theme)
    }

    private func colorBinding(_ keyPath: WritableKeyPath<EditorTheme, String>) -> Binding<Color> {
        Binding {
            Color(hex: theme[keyPath: keyPath])
        } set: { color in
            theme[keyPath: keyPath] = Self.hex(color)
        }
    }

    private static func hex(_ color: Color) -> String {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(round(converted.redComponent * 255)),
                      Int(round(converted.greenComponent * 255)),
                      Int(round(converted.blueComponent * 255)))
    }
}

private struct TypographySettingsView: View {
    @EnvironmentObject private var document: DocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Typography").font(.title2.bold())
                    Text("Fonts and spacing are shared by the editor, reader and live preview.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset") { document.resetTypography() }
            }

            Form {
                Section("Font families") {
                    fontPicker("Writing font", selection: $document.typography.editorFontFamily, systemLabel: "System Text")
                    fontPicker("Preview font", selection: $document.typography.previewFontFamily, systemLabel: "System Text")
                    fontPicker("Code font", selection: $document.typography.codeFontFamily, systemLabel: "System Monospaced")
                }

                Section("Size and spacing") {
                    valueSlider("Editor size", value: $document.typography.editorFontSize, range: 11...28, suffix: "pt")
                    valueSlider("Preview size", value: $document.typography.previewFontSize, range: 11...28, suffix: "pt")
                    valueSlider("Editor line spacing", value: $document.typography.editorLineSpacing, range: 0...16, suffix: "pt")
                    valueSlider("Preview line height", value: $document.typography.previewLineHeight, range: 1.2...2.2, suffix: "×", decimals: 2)
                    valueSlider("Reading width", value: $document.typography.contentWidth, range: 520...1100, suffix: "px", step: 10)
                }

                Section("Live sample") {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Mirror keeps ideas clear and readable.")
                            .font(document.typography.previewFontFamily.map {
                                .custom($0, size: document.typography.previewFontSize)
                            } ?? .system(size: document.typography.previewFontSize))
                        Text("let theme = \"your own\"")
                            .font(document.typography.codeFontFamily.map {
                                .custom($0, size: max(11, document.typography.editorFontSize - 2))
                            } ?? .system(size: max(11, document.typography.editorFontSize - 2), design: .monospaced))
                            .foregroundStyle(document.theme.accent)
                    }
                    .padding(.vertical, 7)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Imported fonts").font(.headline)
                    Text("TTF, OTF and TTC files are copied into Mirror; system fonts are not modified.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import Fonts…", systemImage: "plus") { document.importFonts() }
            }

            if document.importedFonts.isEmpty {
                Text("No fonts imported yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(document.importedFonts, id: \.path) { url in
                            HStack(spacing: 7) {
                                Image(systemName: "textformat")
                                Text(url.lastPathComponent).lineLimit(1)
                                Button { document.removeImportedFont(url) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain).help("Move imported font to Trash")
                            }
                            .font(.caption).padding(.horizontal, 9).padding(.vertical, 6)
                            .background(ContentSurface(theme: document.theme, radius: 8))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fontPicker(_ title: String, selection: Binding<String?>, systemLabel: String) -> some View {
        Picker(LocalizedStringKey(title), selection: selection) {
            Text(LocalizedStringKey(systemLabel)).tag(String?.none)
            Divider()
            ForEach(document.availableFontFamilies, id: \.self) { family in
                Text(family).font(.custom(family, size: 13)).tag(Optional(family))
            }
        }
        .pickerStyle(.menu)
    }

    @ViewBuilder
    private func valueSlider(_ title: String,
                             value: Binding<Double>,
                             range: ClosedRange<Double>,
                             suffix: String,
                             decimals: Int = 0,
                             step: Double = 0.5) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).frame(width: 135, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text("\(value.wrappedValue, specifier: decimals == 0 ? "%.0f" : "%.2f")\(suffix)")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 62, alignment: .trailing)
        }
    }
}

import AppKit
import Foundation

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(2)
}

let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("MirrorDocumentStoreSmoke-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
let markdownURL = root.appendingPathComponent("alpha.md")
let sourceURL = root.appendingPathComponent("beta.swift")
let unknownTextURL = root.appendingPathComponent("notes.customkind")
let imageURL = root.appendingPathComponent("pixel sample.png")
try "# Alpha\r\n\r\nFirst".write(to: markdownURL, atomically: true, encoding: .utf8)
try "let beta = 2\n".write(to: sourceURL, atomically: true, encoding: .utf8)
try "editable text with an uncommon extension\n".write(to: unknownTextURL, atomically: true, encoding: .utf8)
guard let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=") else {
    fail("Could not create image fixture.")
}
try imageData.write(to: imageURL)

Task { @MainActor in
    let store = DocumentStore()
    // Editing fixtures must not inherit the presentation preference from a prior run.
    store.readerMode = false
    store.showPreview = true
    store.openWorkspaceFolder(root)
    for _ in 0..<40 where store.workspaceFiles.count < 4 {
        try? await Task.sleep(for: .milliseconds(50))
    }
    guard store.workspaceFiles.count >= 4 else {
        fail("Workspace indexing did not finish. files=\(store.workspaceFiles.map(\.lastPathComponent))")
    }
    store.searchWorkspace("beta", caseSensitive: false, regularExpression: false)
    for _ in 0..<40 where store.isSearchingWorkspace {
        try? await Task.sleep(for: .milliseconds(50))
    }
    guard store.workspaceSearchResults.contains(where: {
        $0.url.resolvingSymlinksInPath() == sourceURL.resolvingSymlinksInPath() && $0.line == 0
    }) else {
        fail("Workspace full-text search did not find source-file content. files=\(store.workspaceFiles.map(\.lastPathComponent)) results=\(store.workspaceSearchResults)")
    }
    store.searchWorkspace("^# Alpha", caseSensitive: true, regularExpression: true)
    for _ in 0..<40 where store.isSearchingWorkspace {
        try? await Task.sleep(for: .milliseconds(50))
    }
    guard store.workspaceSearchResults.contains(where: {
        $0.url.resolvingSymlinksInPath() == markdownURL.resolvingSymlinksInPath() && $0.line == 0
    }) else {
        fail("Workspace regular-expression search did not find Markdown content.")
    }
    store.openFile(markdownURL)
    store.openFile(sourceURL)
    guard store.openTabs.count == 3,
          store.activeTab?.filePath == sourceURL.path else {
        fail("Opening files did not create independent tabs.")
    }

    store.followWorkspaceToCurrentDocument()
    guard store.workspaceURL == root.standardizedFileURL else { fail("Following a document replaced its enclosing workspace.") }
    store.closeWorkspaceFolder()
    store.followWorkspaceToCurrentDocument()
    guard store.workspaceURL == sourceURL.deletingLastPathComponent().standardizedFileURL else {
        fail("Following a document did not open its folder from an empty workspace.")
    }

    store.openFile(unknownTextURL)
    guard store.fileURL == unknownTextURL.standardizedFileURL,
          store.previewFileURL == nil,
          store.text.contains("uncommon extension") else {
        fail("A valid text file with an uncommon extension was not opened in Mirror's editor.")
    }
    store.openFile(imageURL)
    guard store.previewFileURL == imageURL.standardizedFileURL, store.fileURL == nil else {
        fail("An image file was not routed to Mirror's in-app image preview.")
    }

    guard let markdownTab = store.openTabs.first(where: { $0.filePath == markdownURL.path }),
          var sourceTab = store.openTabs.first(where: { $0.filePath == sourceURL.path }) else {
        fail("Expected file tabs are missing.")
    }
    // Keeping an inactive tab closes text, untitled and image-preview tabs alike.
    let countBeforeInvalidClose = store.openTabs.count
    store.closeOtherTabs(keeping: UUID())
    guard store.openTabs.count == countBeforeInvalidClose else { fail("Invalid keep ID closed documents.") }
    store.closeOtherTabs(keeping: markdownTab.id)
    guard store.openTabs.count == 1, store.activeTabID == markdownTab.id,
          store.fileURL == markdownURL.standardizedFileURL else { fail("Close others did not retain the target document.") }
    store.closeOtherTabs(keeping: markdownTab.id)
    guard store.openTabs.count == 1 else { fail("Close others changed a single-tab workspace.") }
    store.openFile(sourceURL)
    sourceTab = store.openTabs.first(where: { $0.filePath == sourceURL.path })!
    store.selectTab(markdownTab.id)
    guard store.lineEnding == .crlf else { fail("CRLF line endings were not detected.") }
    guard store.insertImageFiles([imageURL]),
          case .insertAtSelection(let insertedImageMarkdown) = store.editorCommand,
          insertedImageMarkdown == "![pixel sample](assets/pixel%20sample.png)",
          FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/pixel sample.png").path) else {
        fail("Image attachment import did not copy the asset and create a relative Markdown reference.")
    }
    guard store.insertImageFiles([imageURL]),
          case .insertAtSelection(let duplicateImageMarkdown) = store.editorCommand,
          duplicateImageMarkdown == "![pixel sample 2](assets/pixel%20sample%202.png)",
          FileManager.default.fileExists(atPath: root.appendingPathComponent("assets/pixel sample 2.png").path) else {
        fail("Image attachment import overwrote a same-named asset instead of choosing a unique name.")
    }
    guard let pastedImage = NSImage(data: imageData), store.insertPastedImage(pastedImage),
          case .insertAtSelection(let pastedImageMarkdown) = store.editorCommand,
          pastedImageMarkdown.hasPrefix("![Pasted Image "), pastedImageMarkdown.contains("](assets/Pasted%20Image%20"),
          (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("assets"),
                                                        includingPropertiesForKeys: nil))?.count == 3 else {
        fail("Clipboard image insertion did not create a PNG asset and Markdown reference.")
    }
    store.selectedRange = NSRange(location: 0, length: 0)
    store.insertMarkdownTable(columns: 3, bodyRows: 2, alignments: [.leading, .center, .trailing])
    guard case .insertAtSelection(let tableMarkdown) = store.editorCommand,
          tableMarkdown.contains("| Column 1 | Column 2 | Column 3 |"),
          tableMarkdown.contains("| --- | :---: | ---: |"),
          tableMarkdown.components(separatedBy: "\n").filter({ $0 == "|  |  |  |" }).count == 2 else {
        fail("Markdown table builder did not generate the requested dimensions and alignments.")
    }
    store.editorSettings.autosaveDelay = 0.5
    store.text += "\nLocal pending edit"
    try "# External\r\n\r\nChanged elsewhere".write(to: markdownURL, atomically: true, encoding: .utf8)
    try? await Task.sleep(for: .milliseconds(900))
    guard store.externalConflict != nil,
          (try String(contentsOf: markdownURL, encoding: .utf8)).contains("Changed elsewhere") else {
        fail("External modification was not detected before autosave.")
    }
    store.reloadExternalVersion()
    try? await Task.sleep(for: .milliseconds(250))
    guard store.externalConflict == nil, store.text.contains("Changed elsewhere"), !store.isDirty else {
        fail("Reloading the external file version failed.")
    }
    store.text += "\nEdited in tab"
    store.selectTab(sourceTab.id)
    let saved = try String(contentsOf: markdownURL, encoding: .utf8)
    guard saved.contains("Edited in tab"),
          !saved.replacingOccurrences(of: "\r\n", with: "").contains("\n") else {
        fail("Tab switch did not preserve CRLF while flushing the edited document.")
    }

    store.selectTab(markdownTab.id)
    guard store.fileURL?.resolvingSymlinksInPath() == markdownURL.resolvingSymlinksInPath(),
          store.externalConflict == nil else {
        fail("Could not return to the Markdown tab for document-history testing.")
    }
    for index in 0..<35 {
        store.text = "# History \(index)\n\nVersion \(index)"
        store.save()
        let diskValue = try String(contentsOf: markdownURL, encoding: .utf8)
        guard diskValue.contains("History \(index)") else {
            fail("Manual history save failed at index \(index). dirty=\(store.isDirty) conflict=\(String(describing: store.externalConflict))")
        }
    }
    guard (try String(contentsOf: markdownURL, encoding: .utf8)).contains("History 34") else {
        fail("Repeated manual saves did not reach the document on disk during history testing.")
    }
    store.loadDocumentHistory()
    for _ in 0..<40 where store.isLoadingDocumentHistory {
        try? await Task.sleep(for: .milliseconds(50))
    }
    guard store.documentHistory.count == 30,
          store.documentHistory.first?.text.contains("History 34") == true,
          let historicalEntry = store.documentHistory.last else {
        fail("Document history did not retain the newest 30 saved versions. count=\(store.documentHistory.count) newest=\(store.documentHistory.first?.text ?? "nil")")
    }
    store.restoreDocumentHistory(historicalEntry)
    guard store.isDirty, store.text == historicalEntry.text else {
        fail("Restoring a document-history version did not return it to the editor as an unsaved change.")
    }
    store.save()

    store.newDocument()
    store.text = "# Recovered tab\n\nUnsaved session text"
    var customTheme = store.duplicateTheme(.paper)
    customTheme.name = "Smoke Theme"
    customTheme.accentHex = "#3366CC"
    store.saveCustomTheme(customTheme)
    store.typography.editorFontSize = 18.5
    store.editorSettings.autoPairDelimiters = false
    guard !store.availableFontFamilies.isEmpty else { fail("System font families were not discovered.") }
    store.readerMode = true
    store.openFile(markdownURL)
    guard store.readerMode else { fail("Reading mode was reset by opening Markdown.") }
    store.openFile(sourceURL)
    guard !store.readerMode else { fail("Source files must retain their editor.") }
    store.openFile(markdownURL)
    guard store.readerMode else { fail("Reading preference was lost after visiting a source file.") }
    store.readerMode = false
    store.showPreview = false
    store.newDocument()
    guard !store.readerMode && !store.showPreview else { fail("Edit mode was reset for a new tab.") }
    store.readerMode = true
    store.persistForApplicationTermination()

    let restored = DocumentStore()
    guard restored.readerMode && !restored.showPreview else { fail("Global presentation preferences did not survive restart.") }
    guard restored.openTabs.count == store.openTabs.count,
          restored.openTabs.contains(where: { $0.isDirty && $0.text.contains("Unsaved session text") }),
          restored.theme.name == "Smoke Theme",
          restored.theme.accentHex == "#3366CC",
          restored.typography.editorFontSize == 18.5,
          restored.editorSettings.autoPairDelimiters == false else {
        fail("Multi-tab recovery session was not restored.")
    }
    print("document-store-smoke-ok tabs=\(restored.openTabs.count)")
    exit(0)
}

RunLoop.main.run()

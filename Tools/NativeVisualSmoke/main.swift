import AppKit
import SwiftUI
import WebKit

let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MirrorNativeVisual")
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
precondition(support.path.hasPrefix(NSHomeDirectory() + "/"))
precondition(NSHomeDirectory().contains("MirrorNativeVisualHome"), "Use an isolated CFFIXED_USER_HOME")

@MainActor
func webViews(_ view: NSView) -> [WKWebView] {
    (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews)
}

@MainActor
func snapshot(_ window: NSWindow, name: String) async throws {
    if ProcessInfo.processInfo.environment["MIRROR_SYSTEM_CAPTURE_HELPER"] != nil {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    try await Task.sleep(for: .milliseconds(700))
    if let helper = ProcessInfo.processInfo.environment["MIRROR_SYSTEM_CAPTURE_HELPER"] {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        capture.arguments = [helper, "--window-id", String(window.windowNumber), "--path", outputURL.appendingPathComponent(name + ".png").path]
        try capture.run()
        capture.waitUntilExit()
        guard capture.terminationStatus == 0 else { throw NSError(domain: "SystemCapture", code: Int(capture.terminationStatus)) }
        print("Captured system window \(name)")
        return
    }
    let view = window.contentView!
    view.layoutSubtreeIfNeeded()
    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: bitmap)
    // WebKit is rendered by another process; request its actual snapshot and
    // place it at the native view coordinates in the window capture.
    let canvas = NSImage(size: view.bounds.size)
    canvas.addRepresentation(bitmap)
    for webView in webViews(view) {
        let configuration = WKSnapshotConfiguration()
        let image = try await webView.takeSnapshot(configuration: configuration)
        let rect = webView.convert(webView.bounds, to: view)
        let target = view.isFlipped ? NSRect(x: rect.minX, y: view.bounds.height - rect.maxY, width: rect.width, height: rect.height) : rect
        canvas.lockFocus()
        image.draw(in: target)
        canvas.unlockFocus()
    }
    let final = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    try final.representation(using: .png, properties: [:])!.write(to: outputURL.appendingPathComponent(name + ".png"))
    print("Captured \(name)")
}

Task { @MainActor in
    do {
        NSApplication.shared.setActivationPolicy(ProcessInfo.processInfo.environment["MIRROR_SYSTEM_CAPTURE_HELPER"] == nil ? .prohibited : .accessory)
        let fixture = outputURL.appendingPathComponent("写作工作区", isDirectory: true)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let markdown = """
        # 让想法，在纸上展开

        一个安静的空间，容纳尚未成形的思考。
        Mirror 把写作、阅读与对话放在同一张桌面上。

        ## 从一张纸开始

        清晰的界面来自秩序：适度的留白、自然的层级，以及随手可用的工具。
        **把注意力留给内容**，让工具轻轻退到文字之后。

        > 写作不是把复杂的想法藏起来，而是给它一个可以展开的形状。

        ### 今天想做的事

        - [x] 收集灵感，写下最初的几句话
        - [ ] 整理成一篇清晰的文章
        - [ ] 圈选一段内容，与 Codex 讨论

        ## 让结构自然浮现

        | 表达 | 方式 | 节奏 |
        | --- | --- | --- |
        | 草稿 | 自由记录 | 轻快 |
        | 阅读 | 梳理思路 | 从容 |

        ```swift
        let idea = "A quiet place to write"
        func unfold() { print(idea) }
        ```

        ---

        让下一页，从这里开始。
        """
        let file = fixture.appendingPathComponent("专注与写作.md")
        try markdown.write(to: file, atomically: true, encoding: .utf8)
        try "# 灵感收集\n\n记下值得保留的一句话。".write(to: fixture.appendingPathComponent("灵感收集.md"), atomically: true, encoding: .utf8)
        let document = DocumentStore()
        document.openWorkspaceFolder(fixture)
        document.openFile(file)
        document.selectTheme(.paper)
        document.showSidebar = true
        document.showFileLibrary = true
        document.showOutline = false
        document.showPreview = true
        document.readerMode = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 860),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView().environmentObject(document))
        window.orderFront(nil)
        try await Task.sleep(for: .seconds(2))
        try await snapshot(window, name: "editor-light")
        document.readerMode = true
        document.showOutline = true
        try await snapshot(window, name: "reader-light")
        document.selectTheme(.ink)
        try await snapshot(window, name: "reader-dark")
        document.readerMode = false
        window.setContentSize(NSSize(width: 1120, height: 620))
        try await snapshot(window, name: "editor-compact-dark")
        document.selectTheme(.midnight)
        precondition(document.theme.accentHex == EditorTheme.midnight.accentHex)
        document.selectTheme(.paper)
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 610), styleMask: [.titled], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        settings.contentView = NSHostingView(rootView: AppearanceSettingsView().environmentObject(document))
        settings.orderFront(nil)
        try await snapshot(settings, name: "settings")
        let palette = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        palette.isReleasedWhenClosed = false
        palette.contentView = NSHostingView(rootView: CommandPaletteView().environmentObject(document))
        palette.orderFront(nil)
        try await snapshot(palette, name: "commands")
        let table = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        table.isReleasedWhenClosed = false
        table.contentView = NSHostingView(rootView: MarkdownTableBuilderView().environmentObject(document))
        table.orderFront(nil)
        try await snapshot(table, name: "table-builder")
        table.close()
        let chat = CodexChatPanel(reference: DocumentReference(text: "写作不是把复杂的想法藏起来，而是给它一个可以展开的形状。", title: "专注与写作.md", fileURL: nil), directory: fixture, theme: .paper)
        chat.showWindow(nil)
        chat.model.draft = "帮我把这句话写得更简洁"
        try await snapshot(chat.window!, name: "codex-light")
        chat.close()
        settings.close()
        palette.close()
        window.close()
        print(outputURL.path)
        exit(0)
    } catch { fputs("Visual smoke failed: \(error)\n", stderr); exit(1) }
}
NSApplication.shared.run()

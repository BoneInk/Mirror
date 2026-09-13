import AppKit
import SwiftUI
import WebKit

@MainActor
func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
}

let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MirrorMemoryVisual")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
precondition(NSHomeDirectory().contains("MirrorMemorySmokeHome"), "Run in an isolated home")

@MainActor
func capture(_ window: NSWindow, _ name: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-l", String(window.windowNumber), output.appendingPathComponent(name + ".png").path]
    try process.run();process.waitUntilExit()
    precondition(process.terminationStatus == 0)
}

NSApplication.shared.setActivationPolicy(.accessory)
Task { @MainActor in
    do {
        let text = "# 引用与对话\n\n引用应标明出处，并对应到原文位置。\n\n点开左侧的小对话标记，就能回顾之前的讨论。\n"
        let quote = "引用应标明出处，并对应到原文位置。"
        let file = output.appendingPathComponent("引用交互示例.md")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let anchor = CodexTextAnchor.capture(in: text, range: (text as NSString).range(of: quote))!
        let record = CodexMemoryRecord(id: UUID(), filePath: file.path, title: file.lastPathComponent, quote: quote,
            location: "原文第 3 行", sourceAnchor: anchor, renderedAnchor: nil, threadID: nil,
            messages: [CodexChatMessage(id: "q", isUser: true, text: "这句话能再简洁一点吗？", displayText: "这句话能再简洁一点吗？"),
                       CodexChatMessage(id: "a", isUser: false, text: "引用要能一眼看出出处，并一键回到原文。")], updatedAt: Date())
        CodexMemoryStore.shared.save(record)
        let document = DocumentStore()
        document.openFile(file)
        document.showSidebar = false
        document.showFileLibrary = false
        document.showPreview = true
        document.readerMode = false
        let window = NSWindow(contentRect: NSRect(x: 70,y: 70,width: 1140,height: 760), styleMask: [.titled,.closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView().environmentObject(document))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .seconds(2))
        let web = descendants(window.contentView!, of: WKWebView.self).first!
        @MainActor func nativeMarkers() -> [NSButton] { descendants(window.contentView!, of: NSButton.self).filter { $0.toolTip?.hasPrefix("回顾") == true } }
        precondition(!nativeMarkers().isEmpty, "Editor memory marker missing")
        precondition(nativeMarkers()[0].menu?.items.first?.title == "删除气泡记录", "Marker right-click deletion missing")
        precondition(CodexMemoryActions.shared.menu(ids: [record.id], fileURL: file.appendingPathExtension("other")).items.isEmpty,
                     "Context actions must not delete another document's records")
        let markerCount = try await web.callAsyncJavaScript("return document.querySelectorAll('[aria-label^=\"回顾对话\"]').length", arguments: [:], in: nil, contentWorld: .defaultClient)
        precondition(markerCount as? Int == 1, "Preview memory marker missing")
        CodexMemoryStore.shared.enabled = false
        try await Task.sleep(for: .milliseconds(200))
        precondition(nativeMarkers().isEmpty, "Disabled editor marker remains")
        let disabledCount = try await web.callAsyncJavaScript("return document.querySelectorAll('[aria-label^=\"回顾对话\"]').length", arguments: [:], in: nil, contentWorld: .defaultClient)
        precondition(disabledCount as? Int == 0, "Disabled preview marker remains")
        CodexMemoryStore.shared.enabled = true
        try await Task.sleep(for: .milliseconds(200))
        let selectionResult = try await web.callAsyncJavaScript("""
        const p=document.querySelector('article p'),r=document.createRange();r.selectNodeContents(p.firstChild);
        window.getSelection().removeAllRanges();window.getSelection().addRange(r);document.dispatchEvent(new Event('selectionchange'));
        return document.querySelector('.mirror-reference-action').textContent;
        """, arguments: [:], in: nil, contentWorld: .defaultClient)
        precondition((selectionResult as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        try await Task.sleep(for: .milliseconds(250))
        let image = try await web.takeSnapshot(configuration: nil)
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("selection-action.png"))
        nativeMarkers()[0].performClick(nil)
        try await Task.sleep(for: .milliseconds(650))
        let headless = CommandLine.arguments.contains("--headless")
        let bubbleWindow = headless ? NSApp.windows.first(where: { $0.isVisible && $0 !== window && $0.firstResponder is CodexInputTextView }) : NSApp.keyWindow
        guard let key = bubbleWindow, let input = key.firstResponder as? NSTextView else {
            for w in NSApp.windows { print("FOCUS", w.isVisible, w.isKeyWindow, String(describing: w.firstResponder), w.frame) }
            fflush(stdout)
            if CommandLine.arguments.contains("--visual") { try capture(window, "focus-debug") }
            fatalError("Restored bubble input is not focused")
        }
        precondition(input.isEditable && input.string.isEmpty)
        if CommandLine.arguments.contains("--visual") { try capture(window, "memory-bubble") }
        let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: key.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        input.keyDown(with: esc)
        try await Task.sleep(for: .milliseconds(250))
        let sourceEditor = descendants(window.contentView!, of: NSTextView.self).first!
        precondition(sourceEditor.selectedRange().length == 0, "Editor selection remains after closing memory")
        precondition(!nativeMarkers().isEmpty, "Closing must keep memory marker")
        let secondRecord = CodexMemoryRecord(id: UUID(), filePath: record.filePath, title: record.title, quote: record.quote,
            location: record.location, sourceAnchor: anchor, renderedAnchor: nil,
            messages: [CodexChatMessage(id: "q2", isUser: true, text: "再解释一下原文", displayText: "再解释一下原文")], updatedAt: Date(), agentProfile: .preset(.claude))
        CodexMemoryStore.shared.save(secondRecord)
        if CommandLine.arguments.contains("--visual") {
            let settings = NSWindow(contentRect: NSRect(x: 100,y: 100,width: 760,height: 610), styleMask: [.titled], backing: .buffered, defer: false)
            settings.isReleasedWhenClosed = false
            settings.contentView = NSHostingView(rootView: AppearanceSettingsView().environmentObject(document))
            settings.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(600))
            try capture(settings, "memory-settings")
            settings.contentView = NSHostingView(rootView: AgentProfileEditor(profile: .preset(.deepseekHarness), save: { _ in }))
            settings.setContentSize(NSSize(width: 560, height: 550))
            try await Task.sleep(for: .milliseconds(300))
            try capture(settings, "agent-profile")
            settings.contentView = NSHostingView(rootView: CodexMemorySettingsView(editing: true).padding(20))
            settings.setContentSize(NSSize(width: 720, height: 570))
            try await Task.sleep(for: .milliseconds(300))
            try capture(settings, "memory-management")
            settings.close()
        }
        try await Task.sleep(for: .milliseconds(250))
        let groupedMenu = nativeMarkers()[0].menu!
        precondition(groupedMenu.items.last?.title == "删除此处全部记录（2）", "Grouped marker must offer individual and whole-group deletion")
        groupedMenu.performActionForItem(at: 0)
        try await Task.sleep(for: .milliseconds(150))
        precondition(CodexMemoryStore.shared.records.count == 1, "Context menu single deletion must preserve the other record")
        let remainingMenu = nativeMarkers()[0].menu!
        precondition(remainingMenu.items.count == 1 && remainingMenu.items[0].title == "删除气泡记录")
        remainingMenu.performActionForItem(at: 0)
        precondition(CodexMemoryStore.shared.records.isEmpty, "Marker right-click action must delete the selected record")
        try await Task.sleep(for: .milliseconds(250))
        precondition(nativeMarkers().isEmpty, "Deleted records must remove editor markers")
        let remaining = try await web.callAsyncJavaScript("return document.querySelectorAll('[aria-label^=\"回顾对话\"]').length", arguments: [:], in: nil, contentWorld: .defaultClient)
        precondition(remaining as? Int == 0, "Deleted records must remove preview markers")
        window.close()
        print("Memory UI passed: editor/preview markers, toggle, saved conversation reopening, selection cleanup, batch marker removal")
        print(headless ? "SKIP: native activation/focus and screenshots (--headless)" : "PASS: native activation and input focus")
        print(output.path)
        exit(0)
    } catch { fputs("Memory UI failed: \(error)\n", stderr); exit(1) }
}
NSApplication.shared.run()

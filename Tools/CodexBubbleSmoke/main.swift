import AppKit
import SwiftUI

@MainActor
func input(in view: NSView?) -> NSTextView? {
    guard let view else { return nil }
    if let text = view as? NSTextView { return text }
    return view.subviews.compactMap { input(in: $0) }.first
}

NSApplication.shared.setActivationPolicy(.accessory)
Task { @MainActor in
    let source = NSWindow(contentRect: NSRect(x: 120, y: 100, width: 900, height: 650), styleMask: [.titled], backing: .buffered, defer: false)
    source.isReleasedWhenClosed = false
    source.title = "Mirror interaction test"
    let view = NSView(frame: NSRect(x: 0,y: 0,width: 900,height: 650))
    source.contentView = view
    source.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    var dismissals = 0
    let selection = ReferenceSelection(text: "引用内容", screenRect: source.convertToScreen(NSRect(x: 120,y: 100,width: 0,height: 20)),
        anchorView: view, dismiss: { dismissals += 1 })
    let reference = DocumentReference(text: selection.text, title: "Test.md", fileURL: nil, selection: selection)
    let first = CodexChatPanel(reference: reference, directory: URL(fileURLWithPath: "/tmp"))
    first.showWindow(nil)
    try? await Task.sleep(for: .milliseconds(600))
    guard let firstWindow = first.presentedWindow, let editor = input(in: firstWindow.contentView) else { fatalError("Missing input") }
    let anchor = selection.screenRect!
    let verticalGap = max(anchor.minY - firstWindow.frame.maxY, firstWindow.frame.minY - anchor.maxY)
    precondition(verticalGap < 24 && verticalGap > -24,
                 "A zero-width selection endpoint must open the bubble next to the text, not the view center")
    precondition(firstWindow.frame.minX <= anchor.midX && firstWindow.frame.maxX >= anchor.midX,
                 "The bubble must remain horizontally aligned with the selection endpoint")
    precondition(firstWindow.isKeyWindow && firstWindow.firstResponder === editor, "Input must be focused after popover opens")
    precondition(editor.isEditable && editor.insertionPointColor == NSColor(EditorTheme.paper.accent))
    editor.insertText("中文 test", replacementRange: editor.selectedRange())
    precondition(first.model.draft == "中文 test", "Native input binding did not update")

    NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
    try? await Task.sleep(for: .milliseconds(100))
    precondition(firstWindow.isVisible && first.model.draft == "中文 test" && dismissals == 0,
                 "Permission-dialog focus loss must preserve bubble, draft and selection")
    precondition(!CodexChatPanel.dismissesExternalClick(bundleID: "com.apple.SecurityAgent", policy: .regular, isOwnProcess: false))
    precondition(!CodexChatPanel.dismissesExternalClick(bundleID: "helper", policy: .accessory, isOwnProcess: false))
    precondition(CodexChatPanel.dismissesExternalClick(bundleID: "com.apple.finder", policy: .regular, isOwnProcess: false))
    let permission = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
    source.beginSheet(permission, completionHandler: nil)
    try? await Task.sleep(for: .milliseconds(100))
    let permissionClick = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: permission.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
    NSApp.postEvent(permissionClick, atStart: false)
    try? await Task.sleep(for: .milliseconds(100))
    precondition(firstWindow.isVisible && dismissals == 0, "Clicks in permission sheets must not close the conversation")
    source.endSheet(permission); permission.orderOut(nil)

    let second = CodexChatPanel(reference: reference, directory: URL(fileURLWithPath: "/tmp"))
    second.showWindow(nil)
    try? await Task.sleep(for: .milliseconds(600))
    precondition(!firstWindow.isVisible && dismissals == 1, "Opening a second bubble must close the first")
    let secondWindow = second.presentedWindow!
    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: secondWindow.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    input(in: secondWindow.contentView)!.keyDown(with: escape)
    try? await Task.sleep(for: .milliseconds(350))
    precondition(!secondWindow.isVisible && dismissals == 2, "Esc must close and clear the source selection")
    let third = CodexChatPanel(reference: reference, directory: URL(fileURLWithPath: "/tmp"))
    third.showWindow(nil)
    try? await Task.sleep(for: .milliseconds(600))
    let thirdWindow = third.presentedWindow!
    let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 10,y: 10), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: source.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    NSApp.postEvent(click, atStart: false)
    try? await Task.sleep(for: .milliseconds(350))
    precondition(!thirdWindow.isVisible && dismissals == 3, "Outside click must dismiss and clear the source selection")
    let composer = CodexInputTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 160))
    composer.string = "中文 test"
    source.contentView = composer
    source.makeKeyAndOrderFront(nil)
    source.makeFirstResponder(composer)
    var submissions = 0
    composer.submit = { submissions += 1 }
    @MainActor func enter(_ modifiers: NSEvent.ModifierFlags = [], keyCode: UInt16 = 36) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: source.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode)!
    }
    let before = composer.string
    precondition(composer.performKeyEquivalent(with: enter(.command)), "Command Return must be handled before menu shortcuts")
    precondition(composer.string == before + "\n" && submissions == 0, "Command Return inserts a newline")
    composer.keyDown(with: enter())
    precondition(submissions == 1, "Return submits")
    composer.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    precondition(composer.hasMarkedText())
    composer.keyDown(with: enter())
    precondition(submissions == 1, "Return must not submit while an IME composition is active")
    composer.unmarkText()
    composer.keyDown(with: enter([], keyCode: 76))
    precondition(submissions == 2, "Keypad Enter submits")
    source.close()
    print("Bubble interaction passed: native input focus, typing, single visible bubble, Esc, outside click, selection cleanup")
    exit(0)
}
NSApplication.shared.run()

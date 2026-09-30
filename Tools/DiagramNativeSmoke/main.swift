import AppKit
import SwiftUI
import WebKit

struct DiagramSmokeView: View {
    @State private var position = ScrollPosition()
    @State private var source = ScrollSource.outline

    var body: some View {
        MarkdownPreview(markdown: """
            # Diagram resize check

            ```mermaid
            flowchart LR
                A[Start] --> B[Review] --> C[Finish]
            ```
            """, revision: 1, title: "Diagram resize check", theme: .paper,
            typography: .standard, preserveSingleLineBreaks: false, baseURL: nil,
            onOpenLocalFile: { _ in }, onReferenceToCodex: { _ in }, syncMode: .off,
            scrollPosition: $position, scrollSource: $source)
    }
}

func webView(in view: NSView) -> WKWebView? {
    if let view = view as? WKWebView { return view }
    return view.subviews.lazy.compactMap { webView(in: $0) }.first
}

let output = FileManager.default.temporaryDirectory.appendingPathComponent("MirrorDiagramNativeSmoke", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let application = NSApplication.shared
application.setActivationPolicy(.regular)
let menu = NSMenu()
let item = NSMenuItem()
let applicationMenu = NSMenu()
applicationMenu.addItem(withTitle: "Quit Diagram Smoke", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.submenu = applicationMenu
menu.addItem(item)
application.mainMenu = menu
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.title = "Mirror Diagram Native Smoke"
window.contentView = NSHostingView(rootView: DiagramSmokeView())
window.center()
window.makeKeyAndOrderFront(nil)
application.activate(ignoringOtherApps: true)
let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
    guard let view = window.contentView, let preview = webView(in: view) else { return }
    preview.evaluateJavaScript("""
      JSON.stringify({ready:window.mirrorEnhancementsDone,
        installer:typeof window.mirrorInstallDiagram,
        tools:document.querySelectorAll('.diagram-tools').length,
        handles:document.querySelectorAll('.diagram-resize').length,
        frameWidth:document.querySelector('.diagram-block')?.getBoundingClientRect().width,
        frameHeight:document.querySelector('.diagram-canvas')?.clientHeight,
        transform:document.querySelector('.diagram-content')?.style.transform,
        zoom:document.querySelector('.diagram-zoom')?.textContent,
        errors:[...document.querySelectorAll('.mermaid-error')].map(node=>node.textContent)})
      """) { result, error in
        let state = result as? String ?? "{\"error\":\"\(String(describing: error))\"}"
        try? state.write(to: output.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
    }
}
application.run()
withExtendedLifetime(timer) {}

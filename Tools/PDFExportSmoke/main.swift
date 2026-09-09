import AppKit
import PDFKit

try MainActor.assumeIsolated {
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MirrorPDFExportSmoke")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var exporter: MarkdownFileExporter?
var completed = false
var failure: Error?
@MainActor func runExport(_ body: String, name: String, fullHTML: Bool = false) throws -> PDFDocument {
    completed = false
    failure = nil
    let url = directory.appendingPathComponent(name + ".pdf")
    exporter = MarkdownFileExporter(html: fullHTML ? body : "<html><body><article>\(body)</article></body></html>", baseURL: nil, operation: .pdf(url)) { result in
        if case .failure(let error) = result { failure = error }
        completed = true
    }
    let deadline = Date().addingTimeInterval(30)
    while !completed && Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    precondition(completed, "Export timed out")
    if let failure { throw failure }
    withExtendedLifetime(exporter) {}
    exporter = nil
    return PDFDocument(url: url)!
}
if CommandLine.arguments.count > 1 {
    let source = URL(fileURLWithPath: CommandLine.arguments[1])
    let markdown = try String(contentsOf: source, encoding: .utf8)
    let html = MarkdownRenderer.document(markdown: markdown, title: source.deletingPathExtension().lastPathComponent,
        theme: .paper, embeddedMermaidScript: MermaidRuntime.script, embeddedMathScript: MathRuntime.script)
    do {
        let document = try runExport(html, name: "document", fullHTML: true)
        print("Document export passed: \(document.pageCount) pages, \(document.outlineRoot?.numberOfChildren ?? 0) root headings")
    } catch {
        print("Document export failed: \(error as NSError)")
        exit(1)
    }
}
let pdf = try runExport("<h1>中文总览</h1><h3>重复标题</h3><p style='height:1800px'>Long content</p><h2>重复标题</h2><h6>深层目录</h6><h1>结束</h1>", name: "headings")
let root = pdf.outlineRoot!
precondition(root.numberOfChildren == 2)
let first = root.child(at: 0)!
precondition(first.label == "中文总览" && first.numberOfChildren == 2)
let skipped = first.child(at: 0)!
let second = first.child(at: 1)!
precondition(skipped.label == "重复标题" && second.label == "重复标题")
precondition(second.child(at: 0)?.label == "深层目录")
precondition(root.child(at: 1)?.label == "结束")
precondition(first.destination!.point.y - second.destination!.point.y > 1700)
precondition(second.destination!.page === pdf.page(at: 0))
let view = PDFView(frame: NSRect(x: 0, y: 0, width: 794, height: 600))
view.document = pdf
view.go(to: second.destination!)
precondition(view.currentPage === pdf.page(at: 0))
let page = pdf.page(at: 0)!
let preview = page.thumbnail(of: NSSize(width: 600, height: 1600), for: .mediaBox)
let bitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("preview.png"))
let multipage = try runExport("<h1>Start</h1><div style='height:18000px'></div><h2>Second page heading</h2>", name: "multipage")
precondition(multipage.pageCount > 1)
let lateHeading = multipage.outlineRoot!.child(at: 0)!.child(at: 0)!
let destination = lateHeading.destination!
precondition(multipage.index(for: destination.page!) == 1)
let headingSelection = multipage.findString("Second page heading", withOptions: []).first!
let headingBounds = headingSelection.bounds(for: destination.page!)
precondition(abs(destination.point.y - headingBounds.maxY) < 35, "Bookmark must land near its heading")
let plain = try runExport("<p>No headings</p>", name: "plain")
precondition(plain.outlineRoot == nil || plain.outlineRoot!.numberOfChildren == 0)
print("PDF export smoke passed: hierarchy, Unicode, duplicates, skipped levels, long-page destinations, navigation, no headings")
print(directory.path)

}

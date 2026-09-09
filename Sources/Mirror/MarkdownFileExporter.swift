import AppKit
import WebKit
import PDFKit

@MainActor
final class MarkdownFileExporter: NSObject, WKNavigationDelegate {
    enum Operation {
        case pdf(URL)
        case printDocument

        var isPrint: Bool {
            if case .printDocument = self { return true }
            return false
        }
    }

    private let operation: Operation
    private let completion: (Result<URL?, Error>) -> Void
    private var webView: WKWebView!

    init(html: String, baseURL: URL?, operation: Operation, completion: @escaping (Result<URL?, Error>) -> Void) {
        self.operation = operation
        self.completion = completion
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 794, height: 1123), configuration: configuration)
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("if(window.mirrorRenderAll){window.mirrorRenderAll()} true") { [weak self] _, _ in
            self?.waitForEnhancements(remainingAttempts: 100)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func waitForEnhancements(remainingAttempts: Int) {
        webView.evaluateJavaScript("window.mirrorEnhancementsDone !== false && window.mirrorMermaidDone !== false && window.mirrorMathDone !== false && (!window.mirrorLayoutStable || window.mirrorLayoutStable())") { [weak self] value, _ in
            guard let self else { return }
            if value as? Bool == true || remainingAttempts <= 0 {
                self.performOperation()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.waitForEnhancements(remainingAttempts: remainingAttempts - 1)
                }
            }
        }
    }

    private func performOperation() {
        switch operation {
        case .pdf(let url):
            exportPDF(to: url)
        case .printDocument:
            let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            let printOperation = webView.printOperation(with: printInfo)
            printOperation.showsPrintPanel = true
            printOperation.showsProgressPanel = true
            if printOperation.run() {
                finish(.success(nil))
            } else {
                finish(.failure(CocoaError(.userCancelled)))
            }
        }
    }

    private func exportPDF(to url: URL) {
        // Read the final layout after fonts, images, math and diagrams have settled.
        let script = """
        (() => ({
            width: document.documentElement.clientWidth,
            height: Math.max(document.documentElement.scrollHeight, document.body.scrollHeight),
            headings: [...document.querySelectorAll('article h1,article h2,article h3,article h4,article h5,article h6')]
                .filter(node => node.getClientRects().length && node.textContent.trim())
                .map(node => ({title: node.textContent.trim(), level: Number(node.tagName.slice(1)),
                    y: node.getBoundingClientRect().top + window.scrollY}))
        }))()
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            guard let layout = value as? [String: Any],
                  let width = layout["width"] as? Double, width > 0,
                  let height = layout["height"] as? Double, height > 0,
                  let headings = layout["headings"] as? [[String: Any]] else {
                self.finish(.failure(error ?? Self.exportError("无法读取文档的标题或页面尺寸。")))
                return
            }
            // WebKit may split a tall rectangle across several PDF pages.
            // Keep the capture rectangle aligned with the measured DOM layout.
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
            self.webView.createPDF(configuration: configuration) { [weak self] result in
                do {
                    let data = try result.get()
                    guard let document = PDFDocument(data: data),
                          document.pageCount > 0 else {
                        throw Self.exportError("WebKit 未生成有效的 PDF 页面（实际页数：\(PDFDocument(data: data)?.pageCount ?? 0)）。")
                    }
                    let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
                    let totalHeight = pages.reduce(CGFloat.zero) { $0 + $1.bounds(for: .mediaBox).height }
                    let root = PDFOutline()
                    var parents: [(level: Int, outline: PDFOutline)] = []
                    for heading in headings {
                        guard let title = heading["title"] as? String,
                              let level = heading["level"] as? Int,
                              let y = heading["y"] as? Double else { continue }
                        let outline = PDFOutline()
                        outline.label = title
                        outline.isOpen = true
                        // DOM coordinates start at the top; PDF coordinates at the bottom.
                        let top = max(0, min(height, y - 8))
                        var offset = top * totalHeight / height
                        var targetPage = pages[pages.count - 1]
                        for candidate in pages {
                            targetPage = candidate
                            let pageHeight = candidate.bounds(for: .mediaBox).height
                            if offset < pageHeight { break }
                            if candidate !== pages.last { offset -= pageHeight }
                        }
                        let bounds = targetPage.bounds(for: .mediaBox)
                        outline.destination = PDFDestination(page: targetPage, at: CGPoint(
                            x: bounds.minX, y: bounds.maxY - min(offset, bounds.height)))
                        while let parent = parents.last, parent.level >= level {
                            parents.removeLast()
                        }
                        let parent = parents.last?.outline ?? root
                        parent.insertChild(outline, at: parent.numberOfChildren)
                        parents.append((level, outline))
                    }
                    if root.numberOfChildren > 0 { document.outlineRoot = root }
                    guard let output = document.dataRepresentation() else {
                        throw Self.exportError("添加目录后无法保存 PDF 数据。")
                    }
                    try output.write(to: url, options: .atomic)
                    self?.finish(.success(url))
                } catch {
                    self?.finish(.failure(error))
                }
            }
        }
    }

    private static func exportError(_ description: String) -> NSError {
        NSError(domain: "Mirror.PDFExport", code: 1, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func finish(_ result: Result<URL?, Error>) {
        webView.navigationDelegate = nil
        completion(result)
    }
}

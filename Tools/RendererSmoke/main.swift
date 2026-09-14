import AppKit
import Foundation
import WebKit

let underscoreCases: [(String, String)] = [
    ("开启 foreign_keys；先解除归属、更新 retention_anchor，再删分类。",
     "开启 foreign_keys；先解除归属、更新 retention_anchor，再删分类。"),
    ("普通记录 retention_anchor 初始等于 copied_at；仅匹配 category_id IS NULL。",
     "普通记录 retention_anchor 初始等于 copied_at；仅匹配 category_id IS NULL。"),
    ("列表按 copied_at 和 id 稳定倒序分页。", "列表按 copied_at 和 id 稳定倒序分页。"),
    ("foo__bar__baz 中文_字段_名称 v1_2_3", "foo__bar__baz 中文_字段_名称 v1_2_3"),
    ("_italic_ and __bold__", "<em>italic</em> and <strong>bold</strong>"),
    ("（_强调_），（__加粗__）。", "（<em>强调</em>），（<strong>加粗</strong>）。"),
    ("_ leading_ and _trailing _", "_ leading_ and _trailing _"),
    (#"\_literal\_ and `foreign_keys`"#, "_literal_ and <code>foreign_keys</code>"),
    ("*italic* and **bold**", "<em>italic</em> and <strong>bold</strong>")
]
for (source, expected) in underscoreCases {
    guard MarkdownRenderer.render(source) == "<p data-source-line=\"0\">\(expected)</p>" else {
        fputs("Underscore rendering regression: \(source)\n", stderr)
        exit(2)
    }
}

let markdown = #"""
---
title: Smoke test
---

Market-ready Markdown
=====================

Inline math $E = mc^2$ and a footnote.[^source]

Visit https://example.com and keep [unsafe](javascript:alert(1)) inert.

> [!TIP]
> Theme-aware alert.

## Trailing heading ###

\*literal emphasis markers\* and **strong text**.

`Simple code`, ``code with a ` backtick``, and a [**formatted** link](https://example.com/formatted).

> A multi-line quote
>
> with a second paragraph, `code`, and an inherited [reference][guide].

+ Plus-marker item

3) Ordered from three

- Parent item
  1. Ordered child
     - [x] Nested task
- Sibling item

[Spaced local link](<docs/My File.md>) and ![Remote image](https://example.com/image.png "Example").

* * *

| Left | Center | Right |
| --- | :---: | ---: |
| A | B | C |

[Reference **link**][guide], ![Reference image][logo], and [Shortcut].

[guide]: <docs/Guide File.md> "Guide title"
[logo]: https://example.com/reference.png "Reference logo"
[shortcut]: https://example.com/shortcut

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

~~~mermaid
sequenceDiagram
    User->>Mirror: Render
    Mirror-->>User: Done
~~~

[^source]: This footnote is rendered locally.
"""#

let html = MarkdownRenderer.document(markdown: markdown,
                                     title: "Renderer smoke test",
                                     theme: .paper,
                                     typography: .standard,
                                     embeddedMermaidScript: MermaidRuntime.script,
                                     embeddedMathScript: MathRuntime.script)

let standardSoftBreak = MarkdownRenderer.render("first line\nsecond line")
let preservedSoftBreak = MarkdownRenderer.render("first line\nsecond line", preserveSingleLineBreaks: true)
guard standardSoftBreak.contains("first line second line"),
      preservedSoftBreak.contains("first line<br>second line") else {
    fputs("Single-line-break preference was not applied correctly.\n", stderr)
    exit(2)
}

let portableRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("MirrorPortableHTML-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: portableRoot, withIntermediateDirectories: true)
let portableImage = portableRoot.appendingPathComponent("sample.png")
let portableImageData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
try portableImageData.write(to: portableImage)
let portableFixture = #"<img src="sample.png"><img src="https://example.com/remote.png">"#
let portableDocument = MarkdownExportResources.makePortable(portableFixture, baseURL: portableRoot)

guard portableDocument.embeddedResourceCount == 1,
      portableDocument.skippedResourceCount == 0,
      portableDocument.html.contains("data:image/png;base64,\(portableImageData.base64EncodedString())"),
      portableDocument.html.contains("https://example.com/remote.png") else {
    fputs("Portable HTML export did not embed local media correctly.\n", stderr)
    exit(2)
}

guard html.contains("data-math="),
      html.contains("class=\"footnotes\""),
      html.contains("<h1 data-source-line="),
      html.contains("class=\"front-matter\""),
      html.contains("alert-tip"),
      html.contains("href=\"https://example.com\""),
      html.contains("Trailing heading</h2>"),
      html.contains("*literal emphasis markers*"),
      html.contains("<code>code with a ` backtick</code>"),
      html.contains("href=\"https://example.com/formatted\"><strong>formatted</strong> link</a>"),
      html.contains("<ol start=\"3\" data-source-line="),
      html.contains("href=\"docs/My File.md\""),
      html.contains("alt=\"Remote image\" title=\"Example\""),
      html.contains("href=\"docs/Guide File.md\" title=\"Guide title\">Reference <strong>link</strong></a>"),
      html.contains("src=\"https://example.com/reference.png\" alt=\"Reference image\""),
      html.contains("window.__mirrorSourceAnchors"),
      html.contains("window.mirrorScrollToPosition"),
      html.contains("article > [data-source-line]"),
      !html.contains("[guide]:"),
      !html.contains("href=\"javascript:"),
      !html.contains("url(fonts/") else {
    fputs("Renderer did not emit expected enhanced Markdown markup.\n", stderr)
    if let range = html.range(of: "example.com/formatted") ?? html.range(of: "docs/Guide") {
        let start = html.index(range.lowerBound, offsetBy: -80, limitedBy: html.startIndex) ?? html.startIndex
        let end = html.index(range.upperBound, offsetBy: 240, limitedBy: html.endIndex) ?? html.endIndex
        fputs(String(html[start..<end]) + "\n", stderr)
    }
    exit(2)
}

final class SmokeDelegate: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var attempts = 0

    init(html: String) {
        super.init()
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1100), configuration: configuration)
        webView.navigationDelegate = self
        webView.loadHTMLString(html, baseURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("if(window.mirrorRenderAll){window.mirrorRenderAll()} true") { [weak self] _, error in
            if let error { self?.fail("Enhancement startup failed: \(error)") }
            else { self?.poll() }
        }
    }

    private func poll() {
        attempts += 1
        webView.evaluateJavaScript("window.mirrorEnhancementsDone !== false && window.mirrorMermaidDone !== false && window.mirrorMathDone !== false && (!window.mirrorLayoutStable || window.mirrorLayoutStable())") { [weak self] value, _ in
            guard let self else { return }
            if value as? Bool == true {
                self.verifyDOM()
            } else if self.attempts < 120 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.poll() }
            } else {
                self.fail("Timed out waiting for math and diagram rendering.")
            }
        }
    }

    private func verifyDOM() {
        let script = """
        (() => {
          const probeSource = 12.4;
          const probeY = window.mirrorYForPosition(12, 0.4);
          const roundTrip = window.mirrorPositionForY(probeY);
          const anchors = window.mirrorSourceAnchors();
          const topBoundary = window.mirrorCurrentPosition(0.35).boundary;
          window.mirrorScrollToPosition(0, 0, 0.35, 'bottom');
          const bottomBoundary = window.mirrorCurrentPosition(0.35).boundary;
          const bottomOffsetError = Math.abs(window.scrollY - window.mirrorMaxScrollY());
          window.mirrorScrollToPosition(0, 0, 0.35, 'top');
          return {
          math: document.querySelectorAll('.katex').length,
          displays: document.querySelectorAll('.katex-display').length,
          diagrams: document.querySelectorAll('.diagram-canvas svg').length,
          footnotes: document.querySelectorAll('.footnotes li').length,
          headings: document.querySelectorAll('h1').length,
          frontMatter: document.querySelectorAll('.front-matter').length,
          alerts: document.querySelectorAll('.markdown-alert').length,
          blockquotes: document.querySelectorAll('blockquote').length,
          unorderedLists: document.querySelectorAll('ul').length,
          orderedFromThree: document.querySelectorAll('ol[start="3"]').length,
          nestedLists: document.querySelectorAll('ul > li > ol > li > ul').length,
          nestedTasks: document.querySelectorAll('ul > li.task .box.done').length,
          thematicBreaks: document.querySelectorAll('hr').length,
          images: document.querySelectorAll('img[alt="Remote image"]').length,
          tables: document.querySelectorAll('.table-wrap table').length,
          centeredCells: document.querySelectorAll('th[style*="center"],td[style*="center"]').length,
          referenceLinks: document.querySelectorAll('a[href="docs/Guide File.md"],a[href="https://example.com/shortcut"]').length,
          referenceImages: document.querySelectorAll('img[src="https://example.com/reference.png"]').length,
          codeWithBacktick: [...document.querySelectorAll('code')].filter(node => node.textContent.includes('`')).length,
          formattedDirectLinks: document.querySelectorAll('a[href="https://example.com/formatted"] strong').length,
          sourceAnchors: anchors.length,
          allSourceNodes: document.querySelectorAll('[data-source-line]').length,
          indexedTopLevelLists: document.querySelectorAll('article > ul[data-source-line],article > ol[data-source-line]').length,
          syncRoundTripError: Math.abs(roundTrip.line + roundTrip.fraction - probeSource),
          topBoundary,
          bottomBoundary,
          bottomOffsetError,
          sourceAnchorsOrdered: anchors.every((anchor, index) => index === 0 || anchor.line > anchors[index - 1].line),
          layoutObserverInstalled: Boolean(window.__mirrorResizeObserver),
          errors: document.querySelectorAll('.math-error,.mermaid-error').length
          };
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self else { return }
            if let error { self.fail("DOM inspection failed: \(error)"); return }
            guard let result = value as? [String: Any],
                  (result["math"] as? Int ?? 0) >= 2,
                  (result["displays"] as? Int ?? 0) >= 1,
                  (result["diagrams"] as? Int ?? 0) == 1,
                  (result["footnotes"] as? Int ?? 0) == 1,
                  (result["headings"] as? Int ?? 0) == 1,
                  (result["frontMatter"] as? Int ?? 0) == 1,
                  (result["alerts"] as? Int ?? 0) == 1,
                  (result["blockquotes"] as? Int ?? 0) == 1,
                  (result["unorderedLists"] as? Int ?? 0) >= 1,
                  (result["orderedFromThree"] as? Int ?? 0) == 1,
                  (result["nestedLists"] as? Int ?? 0) == 1,
                  (result["nestedTasks"] as? Int ?? 0) == 1,
                  (result["thematicBreaks"] as? Int ?? 0) >= 1,
                  (result["images"] as? Int ?? 0) == 1,
                  (result["tables"] as? Int ?? 0) == 1,
                  (result["centeredCells"] as? Int ?? 0) >= 2,
                  (result["referenceLinks"] as? Int ?? 0) == 3,
                  (result["referenceImages"] as? Int ?? 0) == 1,
                  (result["codeWithBacktick"] as? Int ?? 0) == 1,
                  (result["formattedDirectLinks"] as? Int ?? 0) == 1,
                  (result["sourceAnchors"] as? Int ?? 0) > 0,
                  (result["sourceAnchors"] as? Int ?? 0) < (result["allSourceNodes"] as? Int ?? 0),
                  (result["indexedTopLevelLists"] as? Int ?? 0) >= 3,
                  (result["syncRoundTripError"] as? Double ?? 1) < 0.001,
                  (result["topBoundary"] as? String) == "top",
                  (result["bottomBoundary"] as? String) == "bottom",
                  (result["bottomOffsetError"] as? Double ?? 1) < 1,
                  (result["sourceAnchorsOrdered"] as? Bool) == true,
                  (result["layoutObserverInstalled"] as? Bool) == true,
                  (result["errors"] as? Int ?? 1) == 0 else {
                self.fail("Unexpected rendered DOM: \(String(describing: value))")
                return
            }
            let pdfConfiguration = WKPDFConfiguration()
            self.webView.createPDF(configuration: pdfConfiguration) { pdfResult in
                guard let data = try? pdfResult.get(), data.count > 10_000,
                      String(data: data.prefix(4), encoding: .ascii) == "%PDF" else {
                    self.fail("Rendered PDF verification failed.")
                    return
                }
                print("renderer-smoke-ok \(result) pdf-bytes=\(data.count)")
                exit(0)
            }
        }
    }

    private func fail(_ message: String) {
        fputs("\(message)\n", stderr)
        exit(3)
    }
}

_ = NSApplication.shared
let delegate = SmokeDelegate(html: html)
withExtendedLifetime(delegate) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
        fputs("Renderer smoke test timed out.\n", stderr)
        exit(4)
    }
    RunLoop.main.run()
}

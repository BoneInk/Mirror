import Foundation

enum MarkdownRenderer {
    static func document(markdown: String,
                         title: String,
                         theme: EditorTheme,
                         typography: TypographySettings = .standard,
                         preserveSingleLineBreaks: Bool = false,
                         embeddedMermaidScript: String? = nil,
                         embeddedMathScript: String? = nil) -> String {
        let body = render(markdown, preserveSingleLineBreaks: preserveSingleLineBreaks)
        let sourceLineCount = max(1, markdown.components(separatedBy: .newlines).count)
        let hasMath = body.contains("data-math=")
        let mermaidTheme = theme.isDark ? "dark" : "neutral"
        let bodyFont = cssFontFamily(typography.previewFontFamily, fallback: "\"Songti SC\",\"STSong\",\"New York\",Georgia,serif")
        let codeFont = cssFontFamily(typography.codeFontFamily, fallback: "ui-monospace,SFMono-Regular,Menlo,monospace")
        let embeddedRuntime = embeddedMermaidScript.map {
            "<script>\($0.replacingOccurrences(of: "</script", with: "<\\/script", options: .caseInsensitive))</script>"
        } ?? ""
        let embeddedMathRuntime = hasMath ? embeddedMathScript.map {
            "<script>\($0.replacingOccurrences(of: "</script", with: "<\\/script", options: .caseInsensitive))</script>"
        } ?? "" : ""
        // Keep the math stylesheet resident so a live DOM update can introduce
        // equations without requiring a visible page navigation.
        let mathStyle = "<style>\(MathRuntime.style ?? "")</style>"
        let autoRender = (embeddedMermaidScript != nil || embeddedMathScript != nil)
            ? "window.addEventListener('DOMContentLoaded',()=>window.mirrorRenderAll());" : ""
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title><style>
        :root{\(theme.css)}
        *{box-sizing:border-box}html,body{margin:0;min-height:100%;background:var(--bg);color:var(--fg)}
        body{font-size:\(typography.previewFontSize)px;line-height:\(typography.previewLineHeight);font-family:\(bodyFont);padding:42px clamp(38px,6vw,76px) 100px;letter-spacing:.005em}
        article{max-width:\(typography.contentWidth)px;margin:auto;overflow-wrap:anywhere}h1,h2,h3,h4{font-family:\(bodyFont);line-height:1.25;margin:1.7em 0 .6em;letter-spacing:-.025em}h1{font-family:"New York","Songti SC","STSong",Georgia,serif;font-size:clamp(32px,2.8vw,44px);font-weight:600;line-height:1.12;margin:.25em 0 .7em}h2{font-size:1.35em;border-bottom:1px solid var(--line);padding-bottom:.42em}h3{font-size:1.08em}p{margin:1em 0}a{color:var(--accent);text-decoration:none;border-bottom:1px solid color-mix(in srgb,var(--accent) 40%,transparent)}blockquote{margin:1.5em 0;padding:.15em 1.25em;border-left:2px solid var(--accent);color:var(--muted)}code{font-size:85%;font-family:\(codeFont);background:var(--code);padding:.16em .35em;border-radius:5px}pre{margin:0;background:var(--code);padding:1.1em 1.25em;overflow:auto;line-height:1.55}pre code{padding:0;background:transparent}.code-block{margin:1.5em 0;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:var(--code)}.code-header{display:flex;align-items:center;height:30px;padding:0 12px;border-bottom:1px solid var(--line);font:600 10px/1 \(bodyFont);letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}.code-dots{display:flex;gap:5px;margin-right:10px}.code-dots i{width:7px;height:7px;border-radius:50%;background:var(--line)}.tok-keyword{color:var(--syn-key);font-weight:600}.tok-string{color:var(--syn-string)}.tok-comment{color:var(--syn-comment);font-style:italic}.tok-number{color:var(--syn-number)}.tok-type{color:var(--syn-type)}.tok-tag{color:var(--syn-tag)}ul,ol{padding-left:1.4em}li{margin:.35em 0}hr{border:0;border-top:1px solid var(--line);margin:2.5em 0}img,video{max-width:100%;height:auto;border-radius:8px}audio{width:100%}details{margin:1.2em 0;padding:.8em 1em;border:1px solid var(--line);border-radius:8px;background:color-mix(in srgb,var(--code) 35%,transparent)}summary{cursor:pointer;font-weight:650}mark{background:color-mix(in srgb,#ffd95a 55%,transparent);color:inherit;padding:.05em .2em;border-radius:3px}kbd{font:80% \(codeFont);padding:.12em .38em;border:1px solid var(--line);border-bottom-width:2px;border-radius:4px;background:var(--code)}figure{margin:1.5em 0}figcaption{margin-top:.45em;color:var(--muted);font-size:.88em;text-align:center}.task{list-style:none;margin-left:-1.35em}.box{display:inline-flex;width:1.05em;height:1.05em;border:1.5px solid var(--muted);border-radius:3px;margin-right:.55em;vertical-align:-.1em;align-items:center;justify-content:center;color:white;font-size:.75em}.done{background:var(--accent);border-color:var(--accent)}
        .table-wrap{max-width:100%;overflow-x:auto;margin:1.6em 0;border-top:1px solid var(--line)}table{width:100%;min-width:620px;border-collapse:collapse;font-size:.9em;line-height:1.55}th,td{padding:.72em .5em;border-bottom:1px solid var(--line);vertical-align:top}tbody tr:last-child td{border-bottom:0}th{color:var(--muted);font-size:.88em;font-weight:650;white-space:nowrap;text-align:left}td a{word-break:break-word}
        .diagram-block{margin:1.6em 0;border:1px solid var(--line);border-radius:10px;overflow:hidden;background:color-mix(in srgb,var(--code) 30%,var(--bg))}.diagram-canvas{padding:1.25em;overflow:auto;text-align:center}.diagram-canvas svg{display:block;max-width:100%;height:auto;margin:auto}.mermaid-error{white-space:pre-wrap;text-align:left;color:#b43b3b;font:13px/1.55 ui-monospace,SFMono-Regular,Menlo,monospace;background:color-mix(in srgb,#d44 8%,var(--bg));border-radius:6px;padding:1em}
        .math-inline{display:inline-block;max-width:100%;vertical-align:-.08em}.math-block{display:block;max-width:100%;margin:1.5em 0;padding:.75em 1em;overflow-x:auto;text-align:center}.math-error{white-space:pre-wrap;text-align:left;color:#b43b3b;font:13px/1.55 \(codeFont);background:color-mix(in srgb,#d44 8%,var(--bg));border:1px solid color-mix(in srgb,#d44 24%,var(--line));border-radius:7px;padding:.75em}.footnote-ref{font-size:.72em;vertical-align:super;line-height:0;margin-left:.08em}.footnotes{margin-top:3em;padding-top:1em;border-top:1px solid var(--line);font-size:.86em;color:var(--muted)}.footnotes ol{padding-left:1.5em}.footnotes li{padding-left:.25em}.footnotes p{margin:.45em 0}.footnote-backref{margin-left:.35em;border:0}.front-matter{margin:0 0 1.6em;border:1px solid var(--line);border-radius:8px;background:color-mix(in srgb,var(--code) 42%,transparent);overflow:hidden}.front-matter summary{padding:.55em .85em;color:var(--muted);font-size:.8em;text-transform:uppercase;letter-spacing:.08em}.front-matter pre{border-top:1px solid var(--line);border-radius:0;font-size:.8em}.markdown-alert{margin:1.35em 0;padding:.85em 1em;border:1px solid color-mix(in srgb,var(--alert) 40%,var(--line));border-left:4px solid var(--alert);border-radius:7px;background:color-mix(in srgb,var(--alert) 7%,var(--bg))}.markdown-alert-title{display:flex;gap:.45em;align-items:center;margin-bottom:.3em;color:var(--alert);font-size:.82em;font-weight:750;text-transform:uppercase;letter-spacing:.055em}.markdown-alert p{margin:.3em 0}.alert-note{--alert:#3984d6}.alert-tip{--alert:#2a9d68}.alert-important{--alert:#8b5cf6}.alert-warning{--alert:#d58a20}.alert-caution{--alert:#d84b4b}
        /* Opaque content surfaces keep reading separate from navigation glass. */
        ::selection{background:color-mix(in srgb,var(--accent) 22%,transparent)}
        blockquote{background:var(--code);border-left:3px solid var(--accent);border-radius:0 10px 10px 0;padding:.4em 1.3em;color:var(--fg)}
        .code-dots{display:none}.code-header{background:var(--code);height:32px}
        .table-wrap{border:1px solid var(--line);border-radius:10px}
        th{background:var(--code);color:var(--fg)}th,td{padding:.75em .9em}
        @page{size:A4;margin:18mm}@media print{html,body{background:white!important;color:#111!important}body{padding:0;font-size:11pt}article{max-width:none}.code-block,.table-wrap,.diagram-block,blockquote{break-inside:avoid}a{color:inherit;text-decoration:underline}.code-header{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
        </style>\(mathStyle)\(embeddedRuntime)\(embeddedMathRuntime)</head><body><article data-source-lines="\(sourceLineCount)">\(body)</article><script>
        window.__mirrorLayoutChangedAt=performance.now();
        window.mirrorInvalidateLayout=()=>{window.__mirrorSourceAnchors=null;window.__mirrorLayoutChangedAt=performance.now()};
        window.mirrorAnchorTop=anchor=>{const article=document.querySelector('article');if(anchor.edge==='start')return article.getBoundingClientRect().top+window.scrollY;if(anchor.edge==='end')return article.getBoundingClientRect().bottom+window.scrollY;return anchor.element.getBoundingClientRect().top+window.scrollY};
        window.mirrorSourceAnchors=()=>{if(window.__mirrorSourceAnchors)return window.__mirrorSourceAnchors;const article=document.querySelector('article'),total=Math.max(1,Number(article?.dataset.sourceLines)||1);const anchors=[...document.querySelectorAll('article > [data-source-line]')].map(element=>({element,line:Number(element.dataset.sourceLine)||0})).sort((a,b)=>a.line-b.line).filter((anchor,index,list)=>index===0||anchor.line>list[index-1].line);if(!anchors.length||anchors[0].line>0)anchors.unshift({line:0,edge:'start'});if(anchors[anchors.length-1].line<total)anchors.push({line:total,edge:'end'});window.__mirrorSourceAnchors=anchors;return anchors};
        window.mirrorPositionForY=y=>{const anchors=window.mirrorSourceAnchors();if(!anchors.length)return{line:0,fraction:0};let low=0,high=anchors.length;while(low<high){const middle=(low+high)>>1;if(window.mirrorAnchorTop(anchors[middle])<=y)low=middle+1;else high=middle}const before=anchors[Math.max(0,low-1)],after=anchors[Math.min(anchors.length-1,low)],y0=window.mirrorAnchorTop(before),y1=window.mirrorAnchorTop(after),progress=after===before?0:Math.max(0,Math.min(1,(y-y0)/Math.max(1,y1-y0))),source=before.line+progress*(after.line-before.line),line=Math.floor(source);return{line,fraction:Math.max(0,Math.min(1,source-line))}};
        window.mirrorYForPosition=(line,fraction)=>{const anchors=window.mirrorSourceAnchors();if(!anchors.length)return 0;const source=Math.max(0,Number(line)||0)+Math.max(0,Math.min(1,Number(fraction)||0));let low=0,high=anchors.length;while(low<high){const middle=(low+high)>>1;if(anchors[middle].line<=source)low=middle+1;else high=middle}const before=anchors[Math.max(0,low-1)],after=anchors[Math.min(anchors.length-1,low)],span=Math.max(1,after.line-before.line),progress=after===before?0:Math.max(0,Math.min(1,(source-before.line)/span));return window.mirrorAnchorTop(before)+progress*(window.mirrorAnchorTop(after)-window.mirrorAnchorTop(before))};
        window.mirrorMaxScrollY=()=>Math.max(0,Math.max(document.documentElement?.scrollHeight||0,document.body?.scrollHeight||0)-window.innerHeight);
        window.mirrorCurrentPosition=guide=>{const position=window.mirrorPositionForY(window.scrollY+window.innerHeight*Math.max(0,Math.min(1,Number(guide)||0))),maximum=window.mirrorMaxScrollY();position.boundary=window.scrollY<=3?'top':maximum>3&&window.scrollY>=maximum-3?'bottom':'none';return position};
        window.mirrorScrollToLine=(line,fraction,guide)=>{const viewportGuide=window.innerHeight*Math.max(0,Math.min(1,Number(guide)||0)),target=window.mirrorYForPosition(line,fraction)-viewportGuide;if(Math.abs(window.scrollY-target)>2)window.scrollTo(0,target)};
        window.mirrorScrollToPosition=(line,fraction,guide,boundary)=>{let target;if(boundary==='top')target=0;else if(boundary==='bottom')target=window.mirrorMaxScrollY();else return window.mirrorScrollToLine(line,fraction,guide);if(Math.abs(window.scrollY-target)>2)window.scrollTo(0,target)};
        window.mirrorInstallLayoutObserver=()=>{if(window.__mirrorResizeObserver)return;const article=document.querySelector('article');window.__mirrorResizeObserver=new ResizeObserver(window.mirrorInvalidateLayout);if(article)window.__mirrorResizeObserver.observe(article);window.addEventListener('resize',window.mirrorInvalidateLayout,{passive:true})};
        window.mirrorAwaitMedia=async()=>{const waits=[...document.images].map(image=>image.complete?(image.decode?image.decode().catch(()=>{}):Promise.resolve()):Promise.race([new Promise(resolve=>{image.addEventListener('load',resolve,{once:true});image.addEventListener('error',resolve,{once:true})}),new Promise(resolve=>setTimeout(resolve,1500))]));if(document.fonts?.ready)waits.push(document.fonts.ready.catch(()=>{}));await Promise.all(waits)};
        window.mirrorLayoutStable=()=>performance.now()-window.__mirrorLayoutChangedAt>120;
        window.mirrorRenderMermaid=async()=>{window.mirrorMermaidDone=false;try{const nodes=[...document.querySelectorAll('.mermaid:not([data-processed])')];if(!nodes.length)return;if(typeof mermaid==='undefined'){for(const node of nodes){node.classList.add('mermaid-error');node.textContent='Mermaid runtime is unavailable.'}return}mermaid.initialize({startOnLoad:false,securityLevel:'strict',theme:'\(mermaidTheme)',fontFamily:'\(javascriptString(typography.previewFontFamily ?? "-apple-system"))'});for(const node of nodes){const source=node.textContent;try{await mermaid.parse(source);await mermaid.run({nodes:[node],suppressErrors:false})}catch(error){node.removeAttribute('data-processed');node.classList.add('mermaid-error');node.textContent='Diagram syntax error\\n'+(error?.message??String(error))}}}finally{window.mirrorMermaidDone=true}};
        window.mirrorRenderMath=async()=>{window.mirrorMathDone=false;try{const nodes=[...document.querySelectorAll('[data-math]:not([data-math-rendered])')];if(!nodes.length)return;if(typeof katex==='undefined'){for(const node of nodes){node.classList.add('math-error');node.textContent='KaTeX runtime is unavailable.\\n'+node.textContent}return}for(const node of nodes){try{const source=new TextDecoder().decode(Uint8Array.from(atob(node.dataset.math),c=>c.charCodeAt(0)));katex.render(source,node,{displayMode:node.dataset.mathDisplay==='true',throwOnError:false,strict:'warn',trust:false,output:'htmlAndMathml'});node.dataset.mathRendered='true'}catch(error){node.classList.add('math-error');node.textContent='Math syntax error\\n'+(error?.message??String(error))}}}finally{window.mirrorMathDone=true}};
        window.mirrorRenderAll=async()=>{window.mirrorEnhancementsDone=false;try{await Promise.all([window.mirrorRenderMermaid(),window.mirrorRenderMath()]);await window.mirrorAwaitMedia();window.mirrorInstallLayoutObserver();window.mirrorInvalidateLayout()}finally{window.mirrorEnhancementsDone=true}};
        window.mirrorReplaceContent=(content,sourceLines,title,line,fraction,guide,boundary,generation)=>{const article=document.querySelector('article');if(!article)return false;window.__mirrorContentGeneration=Number(generation)||0;if(window.__mirrorResizeObserver){window.__mirrorResizeObserver.disconnect();window.__mirrorResizeObserver=null}article.innerHTML=String(content??'');article.dataset.sourceLines=String(Math.max(1,Number(sourceLines)||1));document.title=String(title??document.title);window.mirrorInvalidateLayout();window.mirrorInstallLayoutObserver();window.mirrorScrollToPosition(line,fraction,guide,boundary);requestAnimationFrame(()=>{if(window.__mirrorContentGeneration===Number(generation))window.mirrorScrollToPosition(line,fraction,guide,boundary)});Promise.resolve(window.mirrorRenderAll()).then(()=>{if(window.__mirrorContentGeneration!==Number(generation))return;window.mirrorScrollToPosition(line,fraction,guide,boundary);requestAnimationFrame(()=>window.mirrorScrollToPosition(line,fraction,guide,boundary))});return true};
        \(autoRender)
        </script></body></html>
        """
    }

    static func render(_ markdown: String, preserveSingleLineBreaks: Bool = false) -> String {
        render(markdown, inheritedReferences: [:], preserveSingleLineBreaks: preserveSingleLineBreaks)
    }

    private static func render(_ markdown: String,
                               inheritedReferences: [String: LinkDefinition],
                               preserveSingleLineBreaks: Bool) -> String {
        let lines = markdown.components(separatedBy: .newlines)
        let frontMatter = frontMatterRange(in: lines)
        let footnotes = collectFootnotes(lines, ignoring: frontMatter)
        let references = collectLinkDefinitions(lines, ignoring: frontMatter,
                                                additionallyIgnoring: footnotes.skippedLines)
        var resolvedReferences = inheritedReferences
        for (identifier, definition) in references.definitions {
            resolvedReferences[identifier] = definition
        }
        var html: [String] = []
        var paragraph: [String] = []
        var inCode = false
        var code: [String] = []
        var codeStart = 0
        var codeLanguage = "text"
        var codeFence: (character: Character, count: Int)?
        var inMathBlock = false
        var math: [String] = []
        var mathStart = 0
        var mathClosing = "$$"
        var paragraphStart: Int?

        func closeParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p data-source-line=\"\(paragraphStart ?? 0)\">\(inline(joinParagraphLines(paragraph, preserveSingleLineBreaks: preserveSingleLineBreaks), footnotes: footnotes.numbers, references: resolvedReferences).replacingOccurrences(of: hardBreakPlaceholder, with: "<br>"))</p>")
            paragraph.removeAll()
            paragraphStart = nil
        }

        var index = 0
        while index < lines.count {
            let sourceLine = index
            let raw = lines[index]
            index += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if sourceLine == 0, let frontMatter {
                closeParagraph()
                let metadata = lines[(frontMatter.lowerBound + 1)..<frontMatter.upperBound].joined(separator: "\n")
                html.append("<details class=\"front-matter\" data-source-line=\"0\"><summary>Document metadata</summary><pre><code>\(escape(metadata))</code></pre></details>")
                index = frontMatter.upperBound + 1
                continue
            }
            if footnotes.skippedLines.contains(sourceLine) || references.skippedLines.contains(sourceLine) {
                closeParagraph(); continue
            }
            if !inCode, !inMathBlock,
               !line.isEmpty,
               index < lines.count,
               let level = setextHeadingLevel(lines[index]) {
                closeParagraph()
                html.append("<h\(level) data-source-line=\"\(sourceLine)\">\(inline(line, footnotes: footnotes.numbers, references: resolvedReferences))</h\(level)>")
                index += 1
                continue
            }
            if !inCode, !inMathBlock,
               index < lines.count,
               let header = parseTableRow(line),
               let alignments = parseTableDelimiter(lines[index]),
               header.count == alignments.count {
                closeParagraph()
                index += 1
                var rows: [[String]] = []
                while index < lines.count,
                      let row = parseTableRow(lines[index]),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    var normalized = Array(row.prefix(header.count))
                    while normalized.count < header.count { normalized.append("") }
                    rows.append(normalized)
                    index += 1
                }
                html.append(renderTable(header: header, alignments: alignments, rows: rows, sourceLine: sourceLine,
                                        footnotes: footnotes.numbers, references: resolvedReferences))
                continue
            }
            if let fence = parseFence(line), !inMathBlock {
                closeParagraph()
                if inCode {
                    if let active = codeFence,
                       fence.character == active.character,
                       fence.count >= active.count,
                       fence.info.isEmpty {
                        html.append(renderCodeBlock(code.joined(separator: "\n"), language: codeLanguage, sourceLine: codeStart))
                        code.removeAll()
                        codeFence = nil
                        inCode = false
                    } else {
                        code.append(raw)
                    }
                } else {
                    codeStart = sourceLine
                    codeLanguage = normalizedLanguage(fence.info)
                    codeFence = (fence.character, fence.count)
                    inCode = true
                }
                continue
            }
            if inCode { code.append(raw); continue }
            if inMathBlock {
                if line == mathClosing {
                    html.append(renderMathBlock(math.joined(separator: "\n"), sourceLine: mathStart))
                    math.removeAll()
                    inMathBlock = false
                } else {
                    math.append(raw)
                }
                continue
            }
            if line == "$$" || line == #"\["# {
                closeParagraph()
                inMathBlock = true
                mathStart = sourceLine
                mathClosing = line == "$$" ? "$$" : #"\]"#
                continue
            }
            if line.hasPrefix("$$"), line.hasSuffix("$$"), line.count > 4 {
                closeParagraph()
                html.append(renderMathBlock(String(line.dropFirst(2).dropLast(2)), sourceLine: sourceLine))
                continue
            }
            if line.isEmpty { closeParagraph(); continue }

            if isHTMLBlockLine(line) {
                closeParagraph()
                html.append(inline(raw, sourceLine: sourceLine, footnotes: footnotes.numbers, references: resolvedReferences))
            } else if let heading = parseHeading(line) {
                closeParagraph()
                html.append("<h\(heading.level) data-source-line=\"\(sourceLine)\">\(inline(heading.title, footnotes: footnotes.numbers, references: resolvedReferences))</h\(heading.level)>")
            } else if isThematicBreak(line) {
                closeParagraph(); html.append("<hr data-source-line=\"\(sourceLine)\">")
            } else if let alertKind = markdownAlertKind(line) {
                closeParagraph()
                var alertLines: [String] = []
                while index < lines.count {
                    let next = lines[index].trimmingCharacters(in: .whitespaces)
                    guard next == ">" || next.hasPrefix("> ") else { break }
                    alertLines.append(next == ">" ? "" : String(next.dropFirst(2)))
                    index += 1
                }
                let content = alertLines.isEmpty ? "" : "<p>\(inline(alertLines.joined(separator: " "), footnotes: footnotes.numbers, references: resolvedReferences))</p>"
                html.append("<aside class=\"markdown-alert alert-\(alertKind.lowercased())\" data-source-line=\"\(sourceLine)\"><div class=\"markdown-alert-title\">\(escape(alertKind))</div>\(content)</aside>")
            } else if line.hasPrefix(">") {
                closeParagraph()
                var quoted = [stripBlockquotePrefix(raw)]
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    quoted.append(stripBlockquotePrefix(lines[index]))
                    index += 1
                }
                html.append("<blockquote data-source-line=\"\(sourceLine)\">\(render(quoted.joined(separator: "\n"), inheritedReferences: resolvedReferences, preserveSingleLineBreaks: preserveSingleLineBreaks))</blockquote>")
            } else if parseListEntry(raw, sourceLine: sourceLine) != nil {
                closeParagraph()
                var entries = [parseListEntry(raw, sourceLine: sourceLine)!]
                while index < lines.count,
                      !footnotes.skippedLines.contains(index),
                      !references.skippedLines.contains(index),
                      let entry = parseListEntry(lines[index], sourceLine: index) {
                    entries.append(entry)
                    index += 1
                }
                html.append(renderList(entries, footnotes: footnotes.numbers, references: resolvedReferences))
            } else {
                if paragraphStart == nil { paragraphStart = sourceLine }
                paragraph.append(String(raw.drop(while: { $0 == " " || $0 == "\t" })))
            }
        }
        if inCode { html.append(renderCodeBlock(code.joined(separator: "\n"), language: codeLanguage, sourceLine: codeStart)) }
        if inMathBlock { html.append(renderMathBlock(math.joined(separator: "\n"), sourceLine: mathStart)) }
        closeParagraph()
        if !footnotes.ordered.isEmpty {
            let items = footnotes.ordered.compactMap { definition -> String? in
                guard footnotes.numbers[definition.id] != nil else { return nil }
                let anchor = safeAnchor(definition.id)
                return "<li id=\"fn-\(anchor)\" data-source-line=\"\(definition.line)\"><p>\(inline(definition.text, footnotes: footnotes.numbers, references: resolvedReferences)) <a class=\"footnote-backref\" href=\"#fnref-\(anchor)\" aria-label=\"Back to reference\">↩</a></p></li>"
            }.joined()
            html.append("<section class=\"footnotes\" aria-label=\"Footnotes\"><ol>\(items)</ol></section>")
        }
        return html.joined(separator: "\n")
    }

    private enum TableAlignment {
        case leading
        case center
        case trailing

        var css: String {
            switch self {
            case .leading: return "left"
            case .center: return "center"
            case .trailing: return "right"
            }
        }
    }

    private static func parseTableDelimiter(_ line: String) -> [TableAlignment]? {
        guard let cells = parseTableRow(line), !cells.isEmpty else { return nil }
        var result: [TableAlignment] = []
        for cell in cells {
            let value = cell.trimmingCharacters(in: .whitespaces)
            guard value.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil else { return nil }
            if value.hasPrefix(":") && value.hasSuffix(":") {
                result.append(.center)
            } else if value.hasSuffix(":") {
                result.append(.trailing)
            } else {
                result.append(.leading)
            }
        }
        return result
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        var value = line.trimmingCharacters(in: .whitespaces)
        guard value.contains("|") else { return nil }
        if value.first == "|" { value.removeFirst() }
        if value.last == "|" { value.removeLast() }

        var cells: [String] = []
        var current = ""
        var isEscaped = false
        var isInCode = false
        for character in value {
            if isEscaped {
                current.append(character)
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
                current.append(character)
            } else if character == "`" {
                isInCode.toggle()
                current.append(character)
            } else if character == "|" && !isInCode {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if isEscaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells.count >= 2 ? cells : nil
    }

    private static func renderTable(header: [String], alignments: [TableAlignment], rows: [[String]], sourceLine: Int,
                                    footnotes: [String: Int], references: [String: LinkDefinition]) -> String {
        let headings = zip(header, alignments).map { cell, alignment in
            "<th style=\"text-align:\(alignment.css)\">\(inline(cell, footnotes: footnotes, references: references))</th>"
        }.joined()
        let body = rows.enumerated().map { rowIndex, row in
            let cells = zip(row, alignments).map { cell, alignment in
                "<td style=\"text-align:\(alignment.css)\">\(inline(cell, footnotes: footnotes, references: references))</td>"
            }.joined()
            return "<tr data-source-line=\"\(sourceLine + rowIndex + 2)\">\(cells)</tr>"
        }.joined()
        return "<div class=\"table-wrap\" data-source-line=\"\(sourceLine)\"><table><thead><tr data-source-line=\"\(sourceLine)\">\(headings)</tr></thead><tbody>\(body)</tbody></table></div>"
    }

    private static func renderCodeBlock(_ code: String, language: String, sourceLine: Int) -> String {
        if language == "mermaid" {
            return """
            <div class="diagram-block" data-source-line="\(sourceLine)">
            <div class="code-header"><span class="code-dots"><i></i><i></i><i></i></span>Mermaid diagram</div>
            <div class="diagram-canvas mermaid">\(escape(code))</div>
            </div>
            """
        }
        let highlighted = highlight(code, language: language)
        return """
        <div class="code-block" data-source-line="\(sourceLine)">
        <div class="code-header"><span class="code-dots"><i></i><i></i><i></i></span>\(escape(language))</div>
        <pre><code class="language-\(escape(language))">\(highlighted)</code></pre>
        </div>
        """
    }

    private static func renderMathBlock(_ source: String, sourceLine: Int) -> String {
        let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return "<div class=\"math-block\" data-source-line=\"\(sourceLine)\" data-math=\"\(mathData(value))\" data-math-display=\"true\">\(escape(value))</div>"
    }

    private static func parseFence(_ line: String) -> (character: Character, count: Int, info: String)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix { $0 == first }.count
        guard count >= 3 else { return nil }
        let info = String(line.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        return (first, count, info)
    }

    private static func normalizedLanguage(_ info: String) -> String {
        var value = info.lowercased().split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "text"
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "{}."))
        let aliases = [
            "js": "javascript", "jsx": "javascript", "mjs": "javascript",
            "ts": "typescript", "tsx": "typescript",
            "py": "python", "rb": "ruby", "kt": "kotlin",
            "sh": "shell", "bash": "shell", "zsh": "shell",
            "yml": "yaml", "html5": "html", "xml": "html",
            "c++": "cpp", "cxx": "cpp", "cs": "csharp",
            "golang": "go", "rs": "rust", "md": "markdown", "mmd": "mermaid"
        ]
        return aliases[value] ?? (value.isEmpty ? "text" : value)
    }

    private static func highlight(_ code: String, language: String) -> String {
        guard language != "text" && language != "plaintext" else { return escape(code) }

        let keywordSets: [String: String] = [
            "swift": "actor any as async await associatedtype break case catch class continue convenience copy consuming default defer deinit didSet distributed do dynamic each else enum extension fallthrough false fileprivate final for func get guard if import in indirect init inout internal is isolated let macro mutating nil nonisolated nonmutating open operator optional override package precedencegroup private protocol public repeat required rethrows return self Self set some static struct subscript super switch throws true try typealias unowned var weak where while willSet",
            "java": "abstract assert boolean break byte case catch char class const continue default do double else enum extends false final finally float for goto if implements import instanceof int interface long native new null package private protected public record return sealed short static strictfp super switch synchronized this throw throws transient true try var void volatile while yield",
            "kotlin": "as break class continue do else false for fun if in interface is null object package return super this throw true try typealias typeof val var when while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam where actual abstract annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg",
            "javascript": "async await break case catch class const continue debugger default delete do else export extends false finally for from function get if import in instanceof let new null of return set static super switch this throw true try typeof undefined var void while with yield",
            "typescript": "abstract any as asserts async await bigint boolean break case catch class const constructor continue declare default delete do else enum export extends false finally for from function get if implements import in infer instanceof interface is keyof let module namespace never new null number object of private protected public readonly require return set static string super switch symbol this throw true try type typeof undefined unique unknown var void while with yield",
            "python": "and as assert async await break class continue def del elif else except false finally for from global if import in is lambda none nonlocal not or pass raise return true try while with yield match case",
            "go": "break default func interface select case defer go map struct chan else goto package switch const fallthrough if range type continue for import return var true false nil",
            "rust": "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while",
            "c": "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while",
            "cpp": "alignas alignof and and_eq asm atomic_cancel atomic_commit atomic_noexcept auto bitand bitor bool break case catch char class compl concept const consteval constexpr constinit const_cast continue co_await co_return co_yield decltype default delete do double dynamic_cast else enum explicit export extern false float for friend goto if inline int long mutable namespace new noexcept not nullptr operator or private protected public reflexpr register reinterpret_cast requires return short signed sizeof static static_assert static_cast struct switch synchronized template this thread_local throw true try typedef typeid typename union unsigned using virtual void volatile wchar_t while xor",
            "csharp": "abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while async await record",
            "sql": "add all alter and any as asc backup between by case check column constraint create database default delete desc distinct drop exec exists foreign from full group having in index inner insert into is join key left like limit not null or order outer primary procedure right rownum select set table top truncate union unique update values view where with",
            "shell": "case do done elif else esac export fi for function if in local readonly return set shift then time trap unset until while",
            "json": "true false null",
            "yaml": "true false null yes no on off",
            "ruby": "alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield",
            "html": "doctype html head body title meta link script style div span main article section nav header footer table thead tbody tr th td ul ol li a img form input button",
            "css": "import media supports keyframes from to important inherit initial unset var calc grid flex block inline none auto relative absolute fixed sticky"
        ]

        let comments: String
        switch language {
        case "python", "ruby", "shell", "yaml": comments = #"#[^\n]*"#
        case "sql": comments = #"--[^\n]*|/\*[\s\S]*?\*/"#
        case "html": comments = #"<!--[\s\S]*?-->"#
        default: comments = #"//[^\n]*|/\*[\s\S]*?\*/"#
        }
        let strings = language == "python"
            ? #"'''[\s\S]*?'''|\"\"\"[\s\S]*?\"\"\"|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"#
            : #"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#
        let keywordList = keywordSets[language] ?? keywordSets[language == "markdown" ? "html" : language] ?? ""
        let keywords = keywordList.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "|")
        let keywordPattern = keywords.isEmpty ? #"(?!)"# : #"\b(?:\#(keywords))\b"#
        let tagPattern = language == "html" ? #"</?[A-Za-z][^>]*>"# : #"(?!)"#
        let typePattern = ["swift", "java", "kotlin", "typescript", "go", "rust", "cpp", "csharp"].contains(language)
            ? #"\b[A-Z][A-Za-z0-9_]*\b"# : #"(?!)"#
        let pattern = "(?<comment>\(comments))|(?<string>\(strings))|(?<tag>\(tagPattern))|(?<keyword>\(keywordPattern))|(?<number>\\b(?:0x[0-9A-Fa-f]+|\\d+(?:\\.\\d+)?)\\b)|(?<type>\(typePattern))"
        let options: NSRegularExpression.Options = language == "sql" ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return escape(code) }

        let source = code as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        var cursor = 0
        var output = ""
        regex.enumerateMatches(in: code, range: fullRange) { match, _, _ in
            guard let match else { return }
            if match.range.location > cursor {
                output += escape(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            let groups = ["comment", "string", "tag", "keyword", "number", "type"]
            let kind = groups.first { match.range(withName: $0).location != NSNotFound } ?? ""
            output += "<span class=\"tok-\(kind)\">\(escape(source.substring(with: match.range)))</span>"
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length {
            output += escape(source.substring(from: cursor))
        }
        return output
    }

    private static func parseHeading(_ line: String) -> (level: Int, title: String)? {
        let count = line.prefix { $0 == "#" }.count
        guard count > 0, count <= 6 else { return nil }
        let remainder = line.dropFirst(count)
        guard remainder.isEmpty || remainder.first == " " || remainder.first == "\t" else { return nil }
        var title = String(remainder).trimmingCharacters(in: .whitespaces)
        if title.range(of: #"\s+#+\s*$"#, options: .regularExpression) != nil {
            title = title.replacingOccurrences(of: #"\s+#+\s*$"#, with: "", options: .regularExpression)
        }
        return (count, title)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.filter { $0 != " " && $0 != "\t" }
        guard compact.count >= 3, let marker = compact.first, ["-", "*", "_"].contains(marker) else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    private static func stripBlockquotePrefix(_ line: String) -> String {
        var value = line.drop(while: { $0 == " " || $0 == "\t" })
        guard value.first == ">" else { return line }
        value = value.dropFirst()
        if value.first == " " { value = value.dropFirst() }
        return String(value)
    }

    private static func setextHeadingLevel(_ line: String) -> Int? {
        let value = line.trimmingCharacters(in: .whitespaces)
        if value.range(of: #"^=+\s*$"#, options: .regularExpression) != nil { return 1 }
        if value.range(of: #"^-+\s*$"#, options: .regularExpression) != nil { return 2 }
        return nil
    }

    private static let hardBreakPlaceholder = "\u{E004}MIRRORBREAK\u{E005}"

    private static func joinParagraphLines(_ lines: [String], preserveSingleLineBreaks: Bool) -> String {
        lines.enumerated().map { index, line in
            guard index < lines.count - 1 else { return line }
            if line.hasSuffix("  ") {
                return String(line.dropLast(2)) + hardBreakPlaceholder
            }
            if line.hasSuffix("\\") {
                return String(line.dropLast()) + hardBreakPlaceholder
            }
            return line + (preserveSingleLineBreaks ? hardBreakPlaceholder : " ")
        }.joined()
    }

    private static func frontMatterRange(in lines: [String]) -> ClosedRange<Int>? {
        guard lines.count >= 3, lines[0].trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        for index in 1..<min(lines.count, 300) {
            let value = lines[index].trimmingCharacters(in: .whitespaces)
            if value == "---" || value == "..." { return 0...index }
        }
        return nil
    }

    private static func markdownAlertKind(_ line: String) -> String? {
        guard line.hasPrefix("> [!"), line.hasSuffix("]") else { return nil }
        let kind = String(line.dropFirst(4).dropLast()).uppercased()
        return ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"].contains(kind) ? kind : nil
    }

    private struct FootnoteDefinition {
        let id: String
        let text: String
        let line: Int
    }

    private struct FootnoteCollection {
        let ordered: [FootnoteDefinition]
        let numbers: [String: Int]
        let skippedLines: Set<Int>
    }

    private struct LinkDefinition {
        let destination: String
        let title: String?
    }

    private struct LinkDefinitionCollection {
        let definitions: [String: LinkDefinition]
        let skippedLines: Set<Int>
    }

    private static func collectLinkDefinitions(_ lines: [String],
                                               ignoring ignoredRange: ClosedRange<Int>?,
                                               additionallyIgnoring ignoredLines: Set<Int>) -> LinkDefinitionCollection {
        let pattern = #"^\s{0,3}\[([^\]^][^\]]*)\]:\s*(?:<([^>]+)>|([^\s]+))(?:\s+(?:\"([^\"]*)\"|'([^']*)'|\(([^)]*)\)))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return LinkDefinitionCollection(definitions: [:], skippedLines: [])
        }
        var definitions: [String: LinkDefinition] = [:]
        var skipped = Set<Int>()
        var activeFence: (character: Character, count: Int)?
        for (index, line) in lines.enumerated() {
            if ignoredRange?.contains(index) == true || ignoredLines.contains(index) { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let fence = parseFence(trimmed) {
                if let active = activeFence {
                    if fence.character == active.character, fence.count >= active.count, fence.info.isEmpty {
                        activeFence = nil
                    }
                } else {
                    activeFence = (fence.character, fence.count)
                }
                continue
            }
            guard activeFence == nil else { continue }
            let source = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { continue }
            let id = normalizedReferenceID(source.substring(with: match.range(at: 1)))
            guard !id.isEmpty else { continue }
            let destinationRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
            let destination = source.substring(with: destinationRange)
            let titleRange = [4, 5, 6].map { match.range(at: $0) }.first { $0.location != NSNotFound }
            let title = titleRange.map { source.substring(with: $0) }
            if definitions[id] == nil {
                definitions[id] = LinkDefinition(destination: destination, title: title)
            }
            skipped.insert(index)
        }
        return LinkDefinitionCollection(definitions: definitions, skippedLines: skipped)
    }

    private static func normalizedReferenceID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func collectFootnotes(_ lines: [String], ignoring ignoredRange: ClosedRange<Int>?) -> FootnoteCollection {
        let definitionPattern = #"^\s*\[\^([^\]]+)\]:\s*(.*)$"#
        guard let definitionRegex = try? NSRegularExpression(pattern: definitionPattern),
              let referenceRegex = try? NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#) else {
            return FootnoteCollection(ordered: [], numbers: [:], skippedLines: [])
        }
        var definitionsByID: [String: FootnoteDefinition] = [:]
        var definitionOrder: [String] = []
        var skipped = Set<Int>()
        var index = 0
        var activeFence: (character: Character, count: Int)?
        while index < lines.count {
            if ignoredRange?.contains(index) == true {
                index += 1
                continue
            }
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if let fence = parseFence(trimmed) {
                if let active = activeFence {
                    if fence.character == active.character, fence.count >= active.count, fence.info.isEmpty {
                        activeFence = nil
                    }
                } else {
                    activeFence = (fence.character, fence.count)
                }
                index += 1
                continue
            }
            if activeFence != nil {
                index += 1
                continue
            }
            let source = lines[index] as NSString
            let range = NSRange(location: 0, length: source.length)
            guard let match = definitionRegex.firstMatch(in: lines[index], range: range) else {
                index += 1
                continue
            }
            let id = source.substring(with: match.range(at: 1)).lowercased()
            var content = source.substring(with: match.range(at: 2))
            let sourceLine = index
            skipped.insert(index)
            index += 1
            while index < lines.count {
                let continuation = lines[index]
                guard continuation.hasPrefix("    ") || continuation.hasPrefix("\t") else { break }
                content += " " + continuation.trimmingCharacters(in: .whitespaces)
                skipped.insert(index)
                index += 1
            }
            if definitionsByID[id] == nil { definitionOrder.append(id) }
            definitionsByID[id] = FootnoteDefinition(id: id, text: content, line: sourceLine)
        }

        var referenceOrder: [String] = []
        var seen = Set<String>()
        for (lineIndex, line) in lines.enumerated() where !skipped.contains(lineIndex) {
            let source = line as NSString
            for match in referenceRegex.matches(in: line, range: NSRange(location: 0, length: source.length)) {
                let id = source.substring(with: match.range(at: 1)).lowercased()
                if definitionsByID[id] != nil, seen.insert(id).inserted { referenceOrder.append(id) }
            }
        }
        let orderedIDs = referenceOrder + definitionOrder.filter { !seen.contains($0) }
        let ordered = orderedIDs.compactMap { definitionsByID[$0] }
        let numbers = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element.id, $0.offset + 1) })
        return FootnoteCollection(ordered: ordered, numbers: numbers, skippedLines: skipped)
    }

    private static func unorderedItem(_ line: String) -> (text: String, task: Bool, box: String)? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") else { return nil }
        var value = String(line.dropFirst(2))
        if value.hasPrefix("[x] ") || value.hasPrefix("[X] ") {
            value = String(value.dropFirst(4)); return (value, true, "<span class=\"box done\">✓</span>")
        }
        if value.hasPrefix("[ ] ") {
            value = String(value.dropFirst(4)); return (value, true, "<span class=\"box\"></span>")
        }
        return (value, false, "")
    }

    private static func orderedItem(_ line: String) -> (text: String, start: Int)? {
        guard let marker = line.firstIndex(where: { $0 == "." || $0 == ")" }),
              !line[..<marker].isEmpty,
              line[..<marker].allSatisfy(\.isNumber),
              line.index(after: marker) < line.endIndex,
              line[line.index(after: marker)] == " ",
              let start = Int(line[..<marker]) else { return nil }
        return (String(line[line.index(marker, offsetBy: 2)...]), start)
    }

    private enum ListKind: String {
        case unordered = "ul"
        case ordered = "ol"
    }

    private struct ListEntry {
        let indent: Int
        let kind: ListKind
        let start: Int
        let text: String
        let task: Bool
        let box: String
        let sourceLine: Int
    }

    private static func parseListEntry(_ raw: String, sourceLine: Int) -> ListEntry? {
        var position = raw.startIndex
        var indentation = 0
        while position < raw.endIndex {
            if raw[position] == " " {
                indentation += 1
            } else if raw[position] == "\t" {
                indentation += 4 - (indentation % 4)
            } else {
                break
            }
            position = raw.index(after: position)
        }
        let content = String(raw[position...])
        if let item = unorderedItem(content) {
            return ListEntry(indent: indentation, kind: .unordered, start: 1, text: item.text,
                             task: item.task, box: item.box, sourceLine: sourceLine)
        }
        if let item = orderedItem(content) {
            return ListEntry(indent: indentation, kind: .ordered, start: item.start, text: item.text,
                             task: false, box: "", sourceLine: sourceLine)
        }
        return nil
    }

    private static func renderList(_ entries: [ListEntry],
                                   footnotes: [String: Int],
                                   references: [String: LinkDefinition]) -> String {
        var cursor = 0

        func level(at indentation: Int) -> String {
            guard cursor < entries.count else { return "" }
            let kind = entries[cursor].kind
            let first = entries[cursor]
            let sourceAttribute = " data-source-line=\"\(first.sourceLine)\""
            let opening = kind == .ordered && first.start != 1
                ? "<ol start=\"\(first.start)\"\(sourceAttribute)>"
                : "<\(kind.rawValue)\(sourceAttribute)>"
            var result = opening

            while cursor < entries.count {
                let entry = entries[cursor]
                guard entry.indent == indentation, entry.kind == kind else { break }
                let className = entry.task ? " class=\"task\"" : ""
                result += "<li data-source-line=\"\(entry.sourceLine)\"\(className)>\(entry.box)"
                result += inline(entry.text, footnotes: footnotes, references: references)
                cursor += 1
                while cursor < entries.count, entries[cursor].indent > indentation {
                    result += level(at: entries[cursor].indent)
                }
                result += "</li>"
            }
            result += "</\(kind.rawValue)>"
            return result
        }

        var result = ""
        while cursor < entries.count {
            result += level(at: entries[cursor].indent)
        }
        return result
    }

    private static let safeHTMLTags: Set<String> = [
        "a", "abbr", "address", "article", "aside", "audio", "b", "bdi", "bdo", "blockquote", "br",
        "caption", "center", "cite", "code", "col", "colgroup", "data", "dd", "del", "details", "dfn",
        "div", "dl", "dt", "em", "figcaption", "figure", "font", "footer", "h1", "h2", "h3", "h4", "h5", "h6",
        "header", "hr", "i", "img", "ins", "kbd", "li", "main", "mark", "nav", "ol", "p", "picture",
        "pre", "q", "s", "samp", "section", "small", "source", "span", "strong", "sub", "summary", "sup",
        "table", "tbody", "td", "tfoot", "th", "thead", "time", "tr", "u", "ul", "var", "video", "wbr"
    ]

    private static let safeHTMLAttributes: Set<String> = [
        "abbr", "align", "alt", "cite", "class", "colspan", "controls", "datetime", "dir", "download",
        "color", "face", "height", "href", "hreflang", "id", "lang", "loop", "media", "muted", "open", "poster", "preload",
        "rel", "reversed", "rowspan", "scope", "span", "src", "start", "style", "target", "title", "type",
        "size", "value", "width"
    ]

    private static let booleanHTMLAttributes: Set<String> = [
        "controls", "download", "loop", "muted", "open", "reversed"
    ]

    private static func isHTMLBlockLine(_ line: String) -> Bool {
        var value = line.trimmingCharacters(in: .whitespaces)
        guard value.hasPrefix("<") else { return false }
        if value.hasPrefix("<!--") { return true }
        value.removeFirst()
        if value.hasPrefix("/") { value.removeFirst() }
        value = value.trimmingCharacters(in: .whitespaces)
        let name = value.prefix { $0.isLetter || $0.isNumber }.lowercased()
        return safeHTMLTags.contains(name)
    }

    private static func inline(_ value: String,
                               sourceLine: Int? = nil,
                               footnotes: [String: Int] = [:],
                               references: [String: LinkDefinition] = [:]) -> String {
        let escapedPunctuation = protectEscapedPunctuation(in: value)
        let protected = protectHTML(in: escapedPunctuation.text, sourceLine: sourceLine)
        let codeSpans = protectCodeSpans(in: protected.text)
        let literals = protectInlineLiterals(in: codeSpans.text, footnotes: footnotes, references: references)
        let referenced = protectReferenceLinks(in: literals.text, definitions: references, footnotes: footnotes)
        var result = escape(referenced.text)
        result = replaceFootnoteReferences(in: result, footnotes: footnotes)
        let replacements: [(String, String)] = [
            (#"\*\*([^*]+)\*\*"#, #"<strong>$1</strong>"#),
            (#"__([^_]+)__"#, #"<strong>$1</strong>"#),
            (#"(?<!\*)\*([^*]+)\*(?!\*)"#, #"<em>$1</em>"#),
            (#"(?<!_)_([^_]+)_(?!_)"#, #"<em>$1</em>"#),
            (#"~~([^~]+)~~"#, #"<del>$1</del>"#)
        ]
        for (pattern, template) in replacements {
            result = result.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        for (index, token) in referenced.tokens.enumerated() {
            result = result.replacingOccurrences(of: referencePlaceholder(index), with: token)
        }
        for (index, token) in literals.tokens.enumerated() {
            result = result.replacingOccurrences(of: inlinePlaceholder(index), with: token)
        }
        for (index, token) in codeSpans.tokens.enumerated() {
            result = result.replacingOccurrences(of: codeSpanPlaceholder(index), with: token)
        }
        for (index, token) in protected.tokens.enumerated() {
            result = result.replacingOccurrences(of: htmlPlaceholder(index), with: token)
        }
        for (index, token) in escapedPunctuation.tokens.enumerated() {
            result = result.replacingOccurrences(of: escapedPunctuationPlaceholder(index), with: token)
        }
        return result
    }

    private static func protectReferenceLinks(in value: String,
                                              definitions: [String: LinkDefinition],
                                              footnotes: [String: Int]) -> (text: String, tokens: [String]) {
        guard !definitions.isEmpty else { return (value, []) }
        let pattern = #"!\[([^\]]+)\](?:\[([^\]]*)\])?|\[([^\]]+)\](?:\[([^\]]*)\])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (value, []) }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        var output = ""
        var tokens: [String] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let isImage = match.range(at: 1).location != NSNotFound
            let labelRange = isImage ? match.range(at: 1) : match.range(at: 3)
            let referenceRange = isImage ? match.range(at: 2) : match.range(at: 4)
            let label = source.substring(with: labelRange)
            let explicitReference = referenceRange.location == NSNotFound ? nil : source.substring(with: referenceRange)
            let id = normalizedReferenceID(explicitReference?.isEmpty == false ? explicitReference! : label)
            let raw = source.substring(with: match.range)
            guard let definition = definitions[id] else {
                output += raw
                cursor = match.range.location + match.range.length
                continue
            }
            let attribute = isImage ? "src" : "href"
            guard isSafeURL(definition.destination, attribute: attribute) else {
                output += raw
                cursor = match.range.location + match.range.length
                continue
            }
            let title = definition.title.map { " title=\"\(escape($0))\"" } ?? ""
            let token: String
            if isImage {
                token = "<img src=\"\(escape(definition.destination))\" alt=\"\(escape(label))\"\(title)>"
            } else {
                token = "<a href=\"\(escape(definition.destination))\"\(title)>\(inline(label, footnotes: footnotes))</a>"
            }
            output += referencePlaceholder(tokens.count)
            tokens.append(token)
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length { output += source.substring(from: cursor) }
        return (output, tokens)
    }

    private static func protectEscapedPunctuation(in value: String) -> (text: String, tokens: [String]) {
        let pattern = ##"\\([!\"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~])"##
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (value, []) }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        var output = ""
        var tokens: [String] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            output += escapedPunctuationPlaceholder(tokens.count)
            tokens.append(escape(source.substring(with: match.range(at: 1))))
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length { output += source.substring(from: cursor) }
        return (output, tokens)
    }

    private static func replaceFootnoteReferences(in value: String, footnotes: [String: Int]) -> String {
        guard !footnotes.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"\[\^([^\]]+)\]"#) else { return value }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        var output = value
        for match in matches.reversed() {
            let id = source.substring(with: match.range(at: 1)).lowercased()
            guard let number = footnotes[id], let range = Range(match.range, in: output) else { continue }
            let anchor = safeAnchor(id)
            output.replaceSubrange(range, with: "<sup class=\"footnote-ref\" id=\"fnref-\(anchor)\"><a href=\"#fn-\(anchor)\">\(number)</a></sup>")
        }
        return output
    }

    private static func safeAnchor(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
                ? String(scalar)
                : "-\(String(scalar.value, radix: 16))-"
        }
        return scalars.joined()
    }

    private static func protectInlineLiterals(in value: String,
                                              footnotes: [String: Int],
                                              references: [String: LinkDefinition]) -> (text: String, tokens: [String]) {
        let pattern = #"!\[([^\]]*)\]\((?:<([^>]+)>|([^\s\)]+))(?:\s+[\"']([^\"']*)[\"'])?\)|\[([^\]]+)\]\((?:<([^>]+)>|([^\s\)]+))(?:\s+[\"']([^\"']*)[\"'])?\)|`([^`\n]+)`|(?<!\\)\$(?!\s)([^$\n]+?)(?<!\s|\\)\$|<((?:https?://|mailto:)[^ >]+|[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})>|(?<![\"'=])(https?://[^\s<>\]\)]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (value, []) }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        var output = ""
        var tokens: [String] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let token: String
            if match.range(at: 1).location != NSNotFound {
                let alt = source.substring(with: match.range(at: 1))
                let urlRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 3)
                let url = source.substring(with: urlRange)
                let title = match.range(at: 4).location == NSNotFound ? "" : " title=\"\(escape(source.substring(with: match.range(at: 4))))\""
                token = isSafeURL(url, attribute: "src")
                    ? "<img src=\"\(escape(url))\" alt=\"\(escape(alt))\"\(title)>"
                    : escape(source.substring(with: match.range))
            } else if match.range(at: 5).location != NSNotFound {
                let label = source.substring(with: match.range(at: 5))
                let urlRange = match.range(at: 6).location != NSNotFound ? match.range(at: 6) : match.range(at: 7)
                let url = source.substring(with: urlRange)
                let title = match.range(at: 8).location == NSNotFound ? "" : " title=\"\(escape(source.substring(with: match.range(at: 8))))\""
                token = isSafeURL(url, attribute: "href")
                    ? "<a href=\"\(escape(url))\"\(title)>\(inline(label, footnotes: footnotes, references: references))</a>"
                    : escape(source.substring(with: match.range))
            } else if match.range(at: 9).location != NSNotFound {
                token = "<code>\(escape(source.substring(with: match.range(at: 9))))</code>"
            } else if match.range(at: 10).location != NSNotFound {
                let math = source.substring(with: match.range(at: 10))
                token = "<span class=\"math-inline\" data-math=\"\(mathData(math))\" data-math-display=\"false\">\(escape(math))</span>"
            } else if match.range(at: 11).location != NSNotFound {
                let value = source.substring(with: match.range(at: 11))
                let url = value.contains("@") && !value.lowercased().hasPrefix("mailto:") ? "mailto:\(value)" : value
                token = "<a href=\"\(escape(url))\">\(escape(value))</a>"
            } else {
                let url = source.substring(with: match.range(at: 12))
                token = "<a href=\"\(escape(url))\">\(escape(url))</a>"
            }
            output += inlinePlaceholder(tokens.count)
            tokens.append(token)
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length { output += source.substring(from: cursor) }
        return (output, tokens)
    }

    private static func protectCodeSpans(in value: String) -> (text: String, tokens: [String]) {
        let pattern = #"(?<!`)(`+)(?!`)([\s\S]*?)(?<!`)\1(?!`)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (value, []) }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        var output = ""
        var tokens: [String] = []
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            var content = source.substring(with: match.range(at: 2))
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if content.count >= 2,
               content.hasPrefix(" "), content.hasSuffix(" "),
               content.contains(where: { !$0.isWhitespace }) {
                content.removeFirst()
                content.removeLast()
            }
            output += codeSpanPlaceholder(tokens.count)
            tokens.append("<code>\(escape(content))</code>")
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length { output += source.substring(from: cursor) }
        return (output, tokens)
    }

    private static func protectHTML(in value: String, sourceLine: Int?) -> (text: String, tokens: [String]) {
        let pattern = #"<!--[\s\S]*?-->|</?[A-Za-z][^>]*>|&(?:#[0-9]+|#x[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (value, []) }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        var output = ""
        var tokens: [String] = []
        var cursor = 0
        var attachedSourceLine = false

        for match in matches {
            if match.range.location > cursor {
                output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let raw = source.substring(with: match.range)
            let sanitized: String?
            if raw.hasPrefix("&") {
                sanitized = raw
            } else if raw.hasPrefix("<!--") {
                sanitized = "<!-- -->"
            } else {
                let line = attachedSourceLine ? nil : sourceLine
                if let tag = sanitizeHTMLTag(raw, sourceLine: line) {
                    sanitized = tag.html
                    if tag.didAttachSourceLine { attachedSourceLine = true }
                } else {
                    sanitized = nil
                }
            }

            if let sanitized {
                output += htmlPlaceholder(tokens.count)
                tokens.append(sanitized)
            } else {
                output += raw
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < source.length { output += source.substring(from: cursor) }
        return (output, tokens)
    }

    private static func sanitizeHTMLTag(_ raw: String, sourceLine: Int?) -> (html: String, didAttachSourceLine: Bool)? {
        var content = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        let isClosing = content.hasPrefix("/")
        if isClosing {
            content.removeFirst()
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let isSelfClosing = content.hasSuffix("/")
        if isSelfClosing { content.removeLast() }
        let name = String(content.prefix { $0.isLetter || $0.isNumber }).lowercased()
        guard safeHTMLTags.contains(name) else { return nil }
        if isClosing { return ("</\(name)>", false) }

        let nameEnd = content.index(content.startIndex, offsetBy: name.count)
        let attributes = String(content[nameEnd...])
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)(?:\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+)))?"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let source = attributes as NSString
        let matches = regex?.matches(in: attributes, range: NSRange(location: 0, length: source.length)) ?? []
        var renderedAttributes: [String] = []
        var didAttachSourceLine = false

        if let sourceLine {
            renderedAttributes.append("data-source-line=\"\(sourceLine)\"")
            didAttachSourceLine = true
        }
        for match in matches {
            let attribute = source.substring(with: match.range(at: 1)).lowercased()
            guard attribute != "data-source-line",
                  safeHTMLAttributes.contains(attribute) || attribute.hasPrefix("aria-") || attribute.hasPrefix("data-") else { continue }
            let valueRanges = [2, 3, 4].map { match.range(at: $0) }
            guard let range = valueRanges.first(where: { $0.location != NSNotFound }) else {
                if booleanHTMLAttributes.contains(attribute) { renderedAttributes.append(attribute) }
                continue
            }
            var attributeValue = source.substring(with: range)
            if ["href", "src", "poster", "cite"].contains(attribute), !isSafeURL(attributeValue, attribute: attribute) { continue }
            if attribute == "style" {
                let lowered = attributeValue.lowercased()
                if ["expression", "javascript:", "url(", "@import", "-webkit-binding"].contains(where: lowered.contains) { continue }
            }
            if attribute == "target", !["_blank", "_self"].contains(attributeValue.lowercased()) {
                attributeValue = "_self"
            }
            renderedAttributes.append("\(attribute)=\"\(escape(attributeValue))\"")
        }

        let suffix = renderedAttributes.isEmpty ? "" : " " + renderedAttributes.joined(separator: " ")
        return ("<\(name)\(suffix)\(isSelfClosing ? " /" : "")>", didAttachSourceLine)
    }

    private static func isSafeURL(_ value: String, attribute: String) -> Bool {
        let url = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if url.hasPrefix("javascript:") || url.hasPrefix("vbscript:") { return false }
        if url.hasPrefix("data:") { return attribute == "src" && url.hasPrefix("data:image/") }
        return true
    }

    private static func htmlPlaceholder(_ index: Int) -> String {
        "\u{E000}MIRRORHTML\(index)\u{E001}"
    }

    private static func inlinePlaceholder(_ index: Int) -> String {
        "\u{E002}MIRRORLITERAL\(index)\u{E003}"
    }

    private static func escapedPunctuationPlaceholder(_ index: Int) -> String {
        "\u{E006}MIRRORESCAPE\(index)\u{E007}"
    }

    private static func referencePlaceholder(_ index: Int) -> String {
        "\u{E008}MIRRORREFERENCE\(index)\u{E009}"
    }

    private static func codeSpanPlaceholder(_ index: Int) -> String {
        "\u{E00A}MIRRORCODESPAN\(index)\u{E00B}"
    }

    private static func mathData(_ source: String) -> String {
        Data(source.utf8).base64EncodedString()
    }

    private static func cssFontFamily(_ family: String?, fallback: String) -> String {
        guard let family, !family.isEmpty else { return fallback }
        let escaped = family.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\",\(fallback)"
    }

    private static func javascriptString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

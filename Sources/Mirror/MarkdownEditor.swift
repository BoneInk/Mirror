import AppKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var command: EditorCommand?
    @Binding var scrollPosition: ScrollPosition
    @Binding var scrollSource: ScrollSource
    let theme: EditorTheme
    let typography: TypographySettings
    let settings: EditorBehaviorSettings
    let isMarkdown: Bool
    let language: String?
    let onInsertImages: ([URL]) -> Bool
    let onPasteImage: (NSImage) -> Bool
    let onReferenceToCodex: (ReferenceSelection) -> Void
    var fileURL: URL? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = UserTrackingScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = MirrorTextView()
        textView.onInsertImages = onInsertImages
        textView.onPasteImage = onPasteImage
        textView.onReferenceToCodex = onReferenceToCodex
        textView.configureMemories(fileURL: fileURL)
        textView.registerForDraggedTypes([.fileURL])
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.setAccessibilityLabel(isMarkdown ? "Markdown source editor" : "Text editor")
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isContinuousSpellCheckingEnabled = settings.checkSpelling && isMarkdown
        textView.isVerticallyResizable = true
        configureWrapping(textView)
        textView.textContainerInset = NSSize(width: 44, height: 34)
        textView.font = resolvedFont(family: isMarkdown ? typography.editorFontFamily : typography.codeFontFamily,
                                     weight: .regular,
                                     size: typography.editorFontSize,
                                     monospacedFallback: true)
        textView.string = text
        scrollView.documentView = textView
        let lineNumberRuler = LineNumberRulerView(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = lineNumberRuler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = settings.showLineNumbers
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.lineNumberRuler = lineNumberRuler
        scrollView.onUserScroll = { [weak coordinator = context.coordinator] in
            coordinator?.requestScrollUpdate(userInitiated: true)
        }
        context.coordinator.startObservingScroll()
        applyTheme(textView)
        context.coordinator.highlight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        context.coordinator.parent = self
        if let textView = textView as? MirrorTextView {
            textView.onInsertImages = onInsertImages
            textView.onPasteImage = onPasteImage
            textView.onReferenceToCodex = onReferenceToCodex
            textView.configureMemories(fileURL: fileURL)
        }
        let configurationChanged = context.coordinator.lastTheme != theme ||
            context.coordinator.lastTypography != typography ||
            context.coordinator.lastSettings != settings ||
            context.coordinator.lastIsMarkdown != isMarkdown ||
            context.coordinator.lastLanguage != language
        if context.coordinator.lastBoundText != text {
            textView.string = text
            context.coordinator.lastBoundText = text
            context.coordinator.lineNumberRuler?.invalidateLineNumbers()
            context.coordinator.highlight()
        }
        if configurationChanged {
            context.coordinator.lastTheme = theme
            context.coordinator.lastTypography = typography
            context.coordinator.lastSettings = settings
            context.coordinator.lastIsMarkdown = isMarkdown
            context.coordinator.lastLanguage = language
            textView.setAccessibilityLabel(isMarkdown ? "Markdown source editor" : "Text editor")
            textView.isContinuousSpellCheckingEnabled = settings.checkSpelling && isMarkdown
            configureWrapping(textView)
            scrollView.rulersVisible = settings.showLineNumbers
            applyTheme(textView)
            context.coordinator.highlight()
        }
        if scrollSource == .outline || (settings.scrollSyncMode != .off && scrollSource == .preview) {
            context.coordinator.scroll(to: scrollPosition)
        }
        if let command {
            if context.coordinator.lastAppliedCommand != command {
                context.coordinator.lastAppliedCommand = command
                context.coordinator.apply(command)
            }
            DispatchQueue.main.async { self.command = nil }
        } else {
            context.coordinator.lastAppliedCommand = nil
        }
    }

    private func applyTheme(_ textView: NSTextView) {
        textView.backgroundColor = NSColor(theme.background)
        textView.textColor = NSColor(theme.foreground)
        textView.insertionPointColor = NSColor(theme.accent)
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor(theme.accent).withAlphaComponent(0.22),
            .foregroundColor: NSColor(theme.foreground)
        ]
    }

    private func configureWrapping(_ textView: NSTextView) {
        textView.isHorizontallyResizable = !settings.wordWrap
        textView.textContainer?.widthTracksTextView = settings.wordWrap
        textView.textContainer?.containerSize = settings.wordWrap
            ? NSSize(width: max(1, textView.bounds.width), height: CGFloat.greatestFiniteMagnitude)
            : NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    }

    private func resolvedFont(family: String?, weight: NSFont.Weight, size: Double, monospacedFallback: Bool) -> NSFont {
        if let family,
           let selected = NSFontManager.shared.font(withFamily: family, traits: [], weight: min(15, max(0, Int(round((weight.rawValue + 1) * 7.5)))), size: size) {
            return selected
        }
        return monospacedFallback
            ? .monospacedSystemFont(ofSize: size, weight: weight)
            : .systemFont(ofSize: size, weight: weight)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        fileprivate weak var lineNumberRuler: LineNumberRulerView?
        var lastTheme: EditorTheme?
        var lastTypography: TypographySettings?
        var lastSettings: EditorBehaviorSettings?
        var lastIsMarkdown: Bool?
        var lastLanguage: String?
        var lastAppliedCommand: EditorCommand?
        private var isHighlighting = false
        private var scrollObserver: NSObjectProtocol?
        private var lineOffsets: [Int] = [0]
        private var lineOffsetsTextLength = -1
        private var lastScrollPublish = 0.0
        private var pendingScrollUpdate: DispatchWorkItem?
        private var scrollRequestGeneration = 0
        private var suppressScrollEventsUntil = 0.0
        private var pendingHighlight: DispatchWorkItem?
        private var currentLineHighlightRange: NSRange?
        private var isApplyingAutomaticPair = false
        fileprivate var lastBoundText: String

        init(_ parent: MarkdownEditor) {
            self.parent = parent
            lastBoundText = parent.text
        }

        deinit {
            pendingHighlight?.cancel()
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }

        func startObservingScroll() {
            guard let scrollView else { return }
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                self?.requestScrollUpdate(userInitiated: false)
            }
        }

        func requestScrollUpdate(userInitiated: Bool) {
            guard parent.settings.scrollSyncMode != .off else { return }
            let textLength = textView?.textStorage?.length ?? 0
            let interval = textLength > 750_000 ? 1.0 / 12.0 : (textLength > 150_000 ? 1.0 / 20.0 : 1.0 / 30.0)
            let now = ProcessInfo.processInfo.systemUptime
            if userInitiated {
                suppressScrollEventsUntil = 0
            } else if now < suppressScrollEventsUntil {
                return
            }
            if parent.scrollSource != .editor { parent.scrollSource = .editor }
            scrollRequestGeneration &+= 1
            let generation = scrollRequestGeneration
            let elapsed = now - lastScrollPublish
            if elapsed >= interval {
                pendingScrollUpdate?.cancel()
                pendingScrollUpdate = nil
                lastScrollPublish = now
                editorDidScroll(generation: generation)
            } else {
                pendingScrollUpdate?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.pendingScrollUpdate = nil
                    self.lastScrollPublish = ProcessInfo.processInfo.systemUptime
                    self.editorDidScroll(generation: generation)
                }
                pendingScrollUpdate = work
                DispatchQueue.main.asyncAfter(deadline: .now() + interval - elapsed, execute: work)
            }
        }

        private func editorDidScroll(generation: Int) {
            guard generation == scrollRequestGeneration,
                  parent.scrollSource == .editor,
                  ProcessInfo.processInfo.systemUptime >= suppressScrollEventsUntil else { return }
            guard let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            lineNumberRuler?.needsDisplay = true
            let textLength = textView.textStorage?.length ?? 0
            if textLength > 750_000 { scheduleHighlight() }
            rebuildLineOffsetsIfNeeded()
            guard let guideFraction = parent.settings.scrollSyncMode.viewportFraction else { return }
            let guideY = scrollView.contentView.bounds.minY
                + scrollView.contentView.bounds.height * CGFloat(guideFraction)
            let containerY = max(0, guideY - textView.textContainerOrigin.y)
            var glyphFraction: CGFloat = 0
            let glyph = layoutManager.glyphIndex(for: NSPoint(x: 1, y: containerY),
                                                 in: textContainer,
                                                 fractionOfDistanceThroughGlyph: &glyphFraction)
            let character = min(layoutManager.characterIndexForGlyph(at: glyph), max(0, textLength - 1))
            let line = lineNumber(for: character)
            let start = lineOffsets[min(line, lineOffsets.count - 1)]
            let end = line + 1 < lineOffsets.count ? lineOffsets[line + 1] : textLength
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: max(1, end - start)), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let fraction = rect.height > 1 ? Double((containerY - rect.minY) / rect.height) : 0
            let currentOffset = scrollView.contentView.bounds.minY
            let maximumOffset = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
            let boundary: ScrollBoundary
            if currentOffset <= 3 {
                boundary = .top
            } else if maximumOffset > 3, currentOffset >= maximumOffset - 3 {
                boundary = .bottom
            } else {
                boundary = .none
            }
            let position = ScrollPosition(line: line,
                                          fraction: min(1, max(0, fraction)),
                                          boundary: boundary)
            if parent.scrollSource == .editor,
               position.boundary == parent.scrollPosition.boundary,
               position.line == parent.scrollPosition.line,
               abs(position.fraction - parent.scrollPosition.fraction) < 0.012 {
                return
            }
            parent.scrollSource = .editor
            parent.scrollPosition = position
        }

        func scroll(to position: ScrollPosition) {
            guard let scrollView,
                  let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            rebuildLineOffsetsIfNeeded()
            let line = min(max(0, position.line), lineOffsets.count - 1)
            let start = lineOffsets[line]
            let end = line + 1 < lineOffsets.count ? lineOffsets[line + 1] : (textView.textStorage?.length ?? 0)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: max(1, end - start)), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let guideFraction = parent.settings.scrollSyncMode.viewportFraction ?? 0.35
            let requested = textView.textContainerOrigin.y
                + rect.minY
                + CGFloat(min(1, max(0, position.fraction))) * rect.height
                - scrollView.contentView.bounds.height * CGFloat(guideFraction)
            let maximum = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
            let target: CGFloat
            switch position.boundary {
            case .top:
                target = 0
            case .bottom:
                target = maximum
            case .none:
                target = min(maximum, max(0, requested))
            }
            guard abs(scrollView.contentView.bounds.minY - target) > 2 else { return }
            pendingScrollUpdate?.cancel()
            pendingScrollUpdate = nil
            scrollRequestGeneration &+= 1
            suppressScrollEventsUntil = ProcessInfo.processInfo.systemUptime + 0.22
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: target))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func rebuildLineOffsetsIfNeeded() {
            guard let textView else { return }
            let length = (textView.string as NSString).length
            guard lineOffsetsTextLength != length else { return }
            lineOffsets = [0]
            for (index, unit) in textView.string.utf16.enumerated() where unit == 10 {
                lineOffsets.append(index + 1)
            }
            lineOffsetsTextLength = length
        }

        private func lineNumber(for character: Int) -> Int {
            var low = 0
            var high = lineOffsets.count
            while low < high {
                let middle = (low + high) / 2
                if lineOffsets[middle] <= character { low = middle + 1 } else { high = middle }
            }
            return max(0, low - 1)
        }

        func textDidChange(_ notification: Notification) {
            guard !isHighlighting, let textView else { return }
            lineNumberRuler?.invalidateLineNumbers()
            lineOffsetsTextLength = -1
            let updatedText = textView.string
            if parent.text != updatedText {
                lastBoundText = updatedText
                parent.text = updatedText
                if (updatedText as NSString).length < 40_000 {
                    highlight()
                } else {
                    scheduleHighlight()
                    updateCurrentLineHighlight()
                }
            }
        }

        private func scheduleHighlight() {
            pendingHighlight?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.pendingHighlight = nil
                self?.highlight()
            }
            pendingHighlight = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09, execute: work)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let range = textView.selectedRange()
            if parent.selection != range { parent.selection = range }
            updateCurrentLineHighlight()
            if parent.settings.typewriterMode {
                DispatchQueue.main.async { [weak self] in self?.centerInsertionPoint() }
            }
        }

        func textView(_ textView: NSTextView,
                      shouldChangeTextIn affectedCharRange: NSRange,
                      replacementString: String?) -> Bool {
            guard parent.settings.autoPairDelimiters,
                  !isApplyingAutomaticPair,
                  let replacementString,
                  replacementString.utf16.count == 1 else { return true }
            let source = textView.string as NSString
            let openingPairs: [Character: Character] = parent.isMarkdown
                ? ["(": ")", "[": "]", "{": "}", "`": "`"]
                : ["(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "`": "`"]
            guard let character = replacementString.first else { return true }

            if openingPairs.values.contains(character), affectedCharRange.length == 0,
               affectedCharRange.location < source.length,
               source.substring(with: NSRange(location: affectedCharRange.location, length: 1)) == replacementString {
                textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1, length: 0))
                return false
            }
            guard let closing = openingPairs[character] else { return true }
            if affectedCharRange.location > 0,
               source.substring(with: NSRange(location: affectedCharRange.location - 1, length: 1)) == "\\" {
                return true
            }
            let selected = affectedCharRange.length > 0 ? source.substring(with: affectedCharRange) : ""
            let pair = replacementString + selected + String(closing)
            isApplyingAutomaticPair = true
            textView.insertText(pair, replacementRange: affectedCharRange)
            isApplyingAutomaticPair = false
            textView.setSelectedRange(NSRange(location: affectedCharRange.location + 1,
                                              length: (selected as NSString).length))
            return false
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                return handleIndent(in: textView, outdent: false)
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                return handleIndent(in: textView, outdent: true)
            }
            guard commandSelector == #selector(NSResponder.insertNewline(_:)),
                  textView.selectedRange().length == 0 else { return false }
            let selection = textView.selectedRange()
            let source = textView.string as NSString
            let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
            let beforeLength = max(0, selection.location - lineRange.location)
            let before = source.substring(with: NSRange(location: lineRange.location, length: beforeLength))

            if parent.isMarkdown, let continuation = markdownContinuation(for: before) {
                if continuation.shouldExit {
                    textView.insertText("", replacementRange: NSRange(location: lineRange.location, length: beforeLength))
                } else {
                    textView.insertText("\n\(continuation.prefix)", replacementRange: selection)
                }
                return true
            }

            let indentation = String(before.prefix { $0 == " " || $0 == "\t" })
            guard !indentation.isEmpty || !parent.isMarkdown else { return false }
            var nextIndentation = indentation
            if !parent.isMarkdown,
               let last = before.trimmingCharacters(in: .whitespaces).last,
               ["{", "[", "("].contains(last) {
                nextIndentation += String(repeating: " ", count: parent.settings.tabWidth)
            }
            textView.insertText("\n\(nextIndentation)", replacementRange: selection)
            return true
        }

        private func handleIndent(in textView: NSTextView, outdent: Bool) -> Bool {
            let range = textView.selectedRange()
            let source = textView.string as NSString
            let lineRange = source.lineRange(for: range)
            if !outdent, range.length == 0 {
                let currentLine = source.substring(with: NSRange(location: lineRange.location,
                                                                  length: range.location - lineRange.location))
                let column = currentLine.reduce(into: 0) { count, character in
                    count += character == "\t" ? parent.settings.tabWidth : 1
                }
                let count = max(1, parent.settings.tabWidth - column % parent.settings.tabWidth)
                textView.insertText(String(repeating: " ", count: count), replacementRange: range)
                return true
            }

            let original = source.substring(with: lineRange)
            let hasTrailingNewline = original.hasSuffix("\n")
            var lines = original.components(separatedBy: "\n")
            if hasTrailingNewline, lines.last == "" { lines.removeLast() }
            let indent = String(repeating: " ", count: parent.settings.tabWidth)
            var removedFromFirstLine = 0
            let transformed = lines.enumerated().map { index, line -> String in
                guard outdent else { return indent + line }
                if line.hasPrefix("\t") {
                    if index == 0 { removedFromFirstLine = 1 }
                    return String(line.dropFirst())
                }
                let spaces = min(parent.settings.tabWidth, line.prefix { $0 == " " }.count)
                if index == 0 { removedFromFirstLine = spaces }
                return String(line.dropFirst(spaces))
            }.joined(separator: "\n") + (hasTrailingNewline ? "\n" : "")
            textView.insertText(transformed, replacementRange: lineRange)
            if range.length == 0 {
                let location = outdent
                    ? max(lineRange.location, range.location - removedFromFirstLine)
                    : range.location
                textView.setSelectedRange(NSRange(location: location, length: 0))
            } else {
                textView.setSelectedRange(NSRange(location: lineRange.location,
                                                  length: (transformed as NSString).length))
            }
            return true
        }

        private func markdownContinuation(for line: String) -> (prefix: String, shouldExit: Bool)? {
            let patterns = [
                #"^(\s*)([-+*])\s+(\[[ xX]\]\s+)?(.*)$"#,
                #"^(\s*)(\d+)([.)])\s+(.*)$"#,
                #"^(\s*)(>+)\s+(.*)$"#
            ]
            for (patternIndex, pattern) in patterns.enumerated() {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let source = line as NSString
                guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: source.length)) else { continue }
                let indent = source.substring(with: match.range(at: 1))
                switch patternIndex {
                case 0:
                    let marker = source.substring(with: match.range(at: 2))
                    let task = match.range(at: 3).location == NSNotFound ? "" : "[ ] "
                    let content = source.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
                    return ("\(indent)\(marker) \(task)", content.isEmpty)
                case 1:
                    let number = Int(source.substring(with: match.range(at: 2))) ?? 0
                    let punctuation = source.substring(with: match.range(at: 3))
                    let content = source.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
                    return ("\(indent)\(number + 1)\(punctuation) ", content.isEmpty)
                default:
                    let marker = source.substring(with: match.range(at: 2))
                    let content = source.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                    return ("\(indent)\(marker) ", content.isEmpty)
                }
            }
            return nil
        }

        func apply(_ command: EditorCommand) {
            guard let textView else { return }
            switch command {
            case .insert(let prefix):
                let range = textView.selectedRange()
                let nsText = textView.string as NSString
                let lineRange = nsText.lineRange(for: range)
                textView.insertText(prefix, replacementRange: NSRange(location: lineRange.location, length: 0))
                textView.setSelectedRange(NSRange(location: range.location + (prefix as NSString).length, length: range.length))
            case .insertAtSelection(let value):
                let range = textView.selectedRange()
                textView.insertText(value, replacementRange: range)
                textView.setSelectedRange(NSRange(location: range.location + (value as NSString).length, length: 0))
            case .wrap(let left, let right, let placeholder):
                let range = textView.selectedRange()
                let selected = range.length > 0 ? (textView.string as NSString).substring(with: range) : placeholder
                let replacement = left + selected + right
                textView.insertText(replacement, replacementRange: range)
                textView.setSelectedRange(NSRange(location: range.location + (left as NSString).length, length: (selected as NSString).length))
            case .select(let range):
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
                textView.window?.makeFirstResponder(textView)
            case .showFind:
                textView.window?.makeFirstResponder(textView)
                let item = NSMenuItem()
                item.tag = NSTextFinder.Action.showFindInterface.rawValue
                textView.performTextFinderAction(item)
            case .showReplace:
                textView.window?.makeFirstResponder(textView)
                let item = NSMenuItem()
                item.tag = NSTextFinder.Action.showReplaceInterface.rawValue
                textView.performTextFinderAction(item)
            }
            if parent.text != textView.string {
                let updatedText = textView.string
                lastBoundText = updatedText
                parent.text = updatedText
                highlight()
            }
        }

        func highlight() {
            guard let textView, let storage = textView.textStorage else { return }
            pendingHighlight?.cancel()
            pendingHighlight = nil
            isHighlighting = true
            lastTheme = parent.theme
            lastTypography = parent.typography
            lastSettings = parent.settings
            lastIsMarkdown = parent.isMarkdown
            lastLanguage = parent.language
            let whole = NSRange(location: 0, length: storage.length)
            let target = highlightRange(in: textView, whole: whole)
            let base = NSColor(parent.theme.foreground)
            storage.beginEditing()
            currentLineHighlightRange = nil
            storage.setAttributes([
                .font: parent.isMarkdown ? editorFont(weight: .regular) : codeFont(weight: .regular),
                .foregroundColor: base,
                .paragraphStyle: paragraphStyle()
            ], range: target)
            if parent.isMarkdown {
                apply(#"(?m)^(#{1,6})\s+(.+)$"#, color: NSColor(parent.theme.foreground), font: editorFont(weight: .bold, size: parent.typography.editorFontSize + 0.5), storage: storage, range: target)
                apply(#"(?s)(?:```.*?```|~~~.*?~~~)"#, color: NSColor(parent.theme.accent), font: codeFont(weight: .regular, size: max(11, parent.typography.editorFontSize - 2.5)), storage: storage, range: target)
                apply(#"(?s)(?:\$\$.*?\$\$|\\\[.*?\\\])"#, color: NSColor(Color(hex: parent.theme.syntaxTypeHex)), font: codeFont(weight: .regular, size: max(11, parent.typography.editorFontSize - 1.5)), storage: storage, range: target)
                apply(#"(?m)(?<!\\)\$(?!\s)[^$\n]+?(?<!\s|\\)\$"#, color: NSColor(Color(hex: parent.theme.syntaxTypeHex)), font: codeFont(weight: .regular, size: max(11, parent.typography.editorFontSize - 1.5)), storage: storage, range: target)
                apply(#"(?m)^\[\^[^\]]+\]:|\[\^[^\]]+\]"#, color: NSColor(Color(hex: parent.theme.syntaxNumberHex)), font: editorFont(weight: .semibold), storage: storage, range: target)
                apply(#"`[^`\n]+`"#, color: NSColor(parent.theme.accent), font: codeFont(weight: .regular, size: max(11, parent.typography.editorFontSize - 2.5)), storage: storage, range: target)
                apply(#"(?m)</?[A-Za-z][^>\n]*>"#, color: NSColor(parent.theme.accent), font: codeFont(weight: .regular, size: max(11, parent.typography.editorFontSize - 2.5)), storage: storage, range: target)
                apply(#"(?m)^(>|-|\*|\d+\.)\s"#, color: NSColor(parent.theme.accent), font: editorFont(weight: .semibold), storage: storage, range: target)
            } else if storage.length <= 2_000_000 {
                highlightSource(storage, range: target)
            }
            storage.endEditing()
            isHighlighting = false
            updateCurrentLineHighlight()
            lineNumberRuler?.needsDisplay = true
        }

        private func highlightSource(_ storage: NSTextStorage, range: NSRange) {
            let language = parent.language?.lowercased() ?? "text"
            let keywords: [String: String] = [
                "swift": "actor as async await break case catch class continue default defer do else enum extension false fileprivate final for func guard if import in init internal is let nil open override private protocol public repeat return self static struct super switch throw throws true try typealias var where while",
                "java": "abstract boolean break byte case catch char class continue default do double else enum extends false final finally float for if implements import instanceof int interface long native new null package private protected public return short static super switch synchronized this throw throws true try void volatile while",
                "javascript": "async await break case catch class const continue debugger default delete do else export extends false finally for from function get if import in instanceof let new null of return set static super switch this throw true try typeof undefined var void while yield",
                "typescript": "abstract any as async await boolean break case catch class const constructor continue declare default delete do else enum export extends false finally for from function if implements import in interface keyof let namespace never new null number object private protected public readonly return static string super switch symbol this throw true try type undefined unknown var void while",
                "python": "and as assert async await break class continue def del elif else except false finally for from global if import in is lambda none nonlocal not or pass raise return true try while with yield match case",
                "go": "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil",
                "rust": "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self static struct super trait true type unsafe use where while",
                "kotlin": "as break class continue do else false for fun if in interface is null object package return super this throw true try typealias val var when while import private protected public override suspend",
                "cpp": "auto bool break case catch char class const continue default delete do double else enum explicit extern false float for friend if inline int long namespace new nullptr operator private protected public return short signed sizeof static struct switch template this throw true try typedef typename union unsigned using virtual void volatile while",
                "sql": "add all alter and as asc between by case create database delete desc distinct drop exists from full group having in index inner insert into is join left like limit not null or order outer primary right select set table union unique update values view where with",
                "shell": "case do done elif else esac export fi for function if in local readonly return set shift then trap unset until while",
                "ruby": "alias and begin break case class def defined do else elsif end ensure false for if in module next nil not or rescue retry return self super then true unless until when while yield"
            ]
            if let list = keywords[language] {
                let terms = list.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "|")
                apply("\\b(?:\(terms))\\b", color: NSColor(Color(hex: parent.theme.syntaxKeywordHex)), font: codeFont(weight: .semibold), storage: storage, options: language == "sql" ? [.caseInsensitive] : [], range: range)
            }
            apply(#"\b(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?)\b"#, color: NSColor(Color(hex: parent.theme.syntaxNumberHex)), font: codeFont(weight: .regular), storage: storage, range: range)
            apply(#"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#, color: NSColor(Color(hex: parent.theme.syntaxStringHex)), font: codeFont(weight: .regular), storage: storage, range: range)
            if ["html", "xml"].contains(language) {
                apply(#"</?[A-Za-z][^>]*>"#, color: NSColor(Color(hex: parent.theme.syntaxTagHex)), font: codeFont(weight: .semibold), storage: storage, range: range)
                apply(#"<!--[\s\S]*?-->"#, color: NSColor(Color(hex: parent.theme.syntaxCommentHex)), font: codeFont(weight: .regular), storage: storage, range: range)
            } else {
                let comments: String
                switch language {
                case "python", "ruby", "shell", "yaml": comments = #"(?m)#[^\n]*$"#
                case "sql": comments = #"(?m)--[^\n]*$|/\*[\s\S]*?\*/"#
                default: comments = #"(?m)//[^\n]*$|/\*[\s\S]*?\*/"#
                }
                apply(comments, color: NSColor(Color(hex: parent.theme.syntaxCommentHex)), font: codeFont(weight: .regular), storage: storage, range: range)
            }
        }

        private func apply(_ pattern: String,
                           color: NSColor,
                           font: NSFont,
                           storage: NSTextStorage,
                           options: NSRegularExpression.Options = [],
                           range: NSRange) {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            regex.enumerateMatches(in: storage.string, range: range) { result, _, _ in
                guard let result else { return }
                storage.addAttributes([.foregroundColor: color, .font: font], range: result.range)
            }
        }

        private func highlightRange(in textView: NSTextView, whole: NSRange) -> NSRange {
            guard whole.length > 750_000,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return whole }
            let glyphs = layoutManager.glyphRange(forBoundingRect: textView.visibleRect.insetBy(dx: 0, dy: -1200), in: container)
            let visibleCharacters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let start = max(0, visibleCharacters.location - 8_000)
            let end = min(whole.length, visibleCharacters.location + visibleCharacters.length + 8_000)
            return NSRange(location: start, length: max(0, end - start))
        }

        private func paragraphStyle() -> NSParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = parent.typography.editorLineSpacing
            style.paragraphSpacing = 3
            let spaceWidth = codeFont(weight: .regular).advancement(forGlyph: codeFont(weight: .regular).glyph(withName: "space")).width
            style.defaultTabInterval = max(1, spaceWidth) * CGFloat(parent.settings.tabWidth)
            style.tabStops = []
            return style
        }

        private func updateCurrentLineHighlight() {
            guard !isHighlighting, let textView, let storage = textView.textStorage else { return }
            if let previous = currentLineHighlightRange,
               previous.location + previous.length <= storage.length {
                storage.removeAttribute(.backgroundColor, range: previous)
            }
            currentLineHighlightRange = nil
            guard parent.settings.highlightCurrentLine, storage.length > 0 else { return }
            let location = min(textView.selectedRange().location, storage.length)
            let line = (textView.string as NSString).lineRange(for: NSRange(location: location, length: 0))
            storage.addAttribute(.backgroundColor, value: NSColor(parent.theme.accent).withAlphaComponent(parent.theme.isDark ? 0.08 : 0.055), range: line)
            currentLineHighlightRange = line
        }

        private func centerInsertionPoint() {
            guard let textView, let scrollView else { return }
            let range = textView.selectedRange()
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            let glyph = layoutManager.glyphRange(forCharacterRange: NSRange(location: min(range.location, textView.string.utf16.count), length: 0), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyph, in: container)
            let target = textView.textContainerOrigin.y + rect.midY - scrollView.contentView.bounds.height / 2
            let maximum = max(0, textView.bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: min(maximum, max(0, target))))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func editorFont(weight: NSFont.Weight, size: Double? = nil) -> NSFont {
            resolvedFont(family: parent.typography.editorFontFamily,
                         weight: weight,
                         size: size ?? max(11, parent.typography.editorFontSize - 2),
                         monospacedFallback: true)
        }

        private func codeFont(weight: NSFont.Weight, size: Double? = nil) -> NSFont {
            resolvedFont(family: parent.typography.codeFontFamily,
                         weight: weight,
                         size: size ?? max(11, parent.typography.editorFontSize - (parent.isMarkdown ? 2 : 0)),
                         monospacedFallback: true)
        }

        private func resolvedFont(family: String?, weight: NSFont.Weight, size: Double, monospacedFallback: Bool) -> NSFont {
            if let family,
               let selected = NSFontManager.shared.font(withFamily: family, traits: [], weight: min(15, max(0, Int(round((weight.rawValue + 1) * 7.5)))), size: size) {
                return selected
            }
            return monospacedFallback
                ? .monospacedSystemFont(ofSize: size, weight: weight)
                : .systemFont(ofSize: size, weight: weight)
        }
    }
}

private final class MirrorTextView: NSTextView {
    var onInsertImages: (([URL]) -> Bool)?
    var onPasteImage: ((NSImage) -> Bool)?
    var onReferenceToCodex: ((ReferenceSelection) -> Void)?

    private var memoryFileURL: URL?
    private var memoryObserver: NSObjectProtocol?
    private var memoryButtons: [NSButton] = []
    private var memoryRanges: [UUID: NSRange] = [:]
    private var memoryGroups: [String: [UUID]] = [:]
    private var pendingMemoryRect = NSRect.zero
    private var markerSignature = ""

    func configureMemories(fileURL: URL?) {
        memoryFileURL = fileURL
        if memoryObserver == nil {
            memoryObserver = NotificationCenter.default.addObserver(forName: CodexMemoryStore.changed, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMemoryMarkers(force: true) }
            }
        }
        DispatchQueue.main.async { [weak self] in self?.refreshMemoryMarkers() }
    }
    deinit { if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) } }
    override func didChangeText() {
        super.didChangeText()
        refreshMemoryMarkers(force: true)
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        DispatchQueue.main.async { [weak self] in self?.refreshMemoryMarkers(force: true) }
    }
    func clearReferenceSelection(expected: NSRange) {
        let range = selectedRange()
        guard range == expected else { return }
        setSelectedRange(NSRange(location: min(range.location, (string as NSString).length), length: 0))
    }
    private func refreshMemoryMarkers(force: Bool = false) {
        let records = CodexMemoryStore.shared.records(for: memoryFileURL)
        let signature = (memoryFileURL?.path ?? "") + String(string.hashValue) + records.map { $0.id.uuidString }.joined()
        guard force || markerSignature != signature else { return }
        markerSignature = signature
        memoryButtons.forEach { $0.removeFromSuperview() }; memoryButtons = []; memoryRanges = [:]; memoryGroups = [:]
        guard let layoutManager, let textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        var occupied: [Int: NSButton] = [:]
        for record in records {
            guard let range = record.sourceAnchor?.resolve(in: string) else { continue }
            let glyph = layoutManager.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyph, in: textContainer).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            let row = Int(rect.midY)
            memoryRanges[record.id] = range
            if let button = occupied[row], let key = button.identifier?.rawValue {
                memoryGroups[key, default: []].append(record.id)
                button.toolTip = "回顾 \(memoryGroups[key]!.count) 条对话"
                continue
            }
            let button = NSButton(image: NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "回顾对话")!, target: self, action: #selector(openMemory(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(record.id.uuidString)
            button.isBordered = false
            button.contentTintColor = .controlAccentColor
            button.toolTip = "回顾对话：" + String(record.quote.prefix(60))
            button.frame = NSRect(x: max(2, textContainerOrigin.x - 28), y: rect.minY, width: 18, height: 18)
            addSubview(button); memoryButtons.append(button); occupied[row] = button; memoryGroups[record.id.uuidString] = [record.id]
        }
    }
    @objc private func openMemory(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue, let ids = memoryGroups[key], let window else { return }
        pendingMemoryRect = window.convertToScreen(convert(sender.frame, to: nil))
        if ids.count == 1 { openMemory(id: ids[0]); return }
        let menu = NSMenu()
        for record in CodexMemoryStore.shared.records(for: memoryFileURL) where ids.contains(record.id) {
            let item = NSMenuItem(title: record.menuTitle, action: #selector(chooseMemory(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = record.id.uuidString; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.frame.maxX, y: sender.frame.maxY), in: self)
    }
    @objc private func chooseMemory(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let id = UUID(uuidString: value) { openMemory(id: id) }
    }
    private func openMemory(id: UUID) {
        guard let record = CodexMemoryStore.shared.records(for: memoryFileURL).first(where: { $0.id == id }),
              let range = memoryRanges[id] else { return }
        let rect = pendingMemoryRect
        setSelectedRange(range)
        onReferenceToCodex?(ReferenceSelection(text: record.quote, location: record.location, screenRect: rect,
            reveal: { [weak self] in
                guard let self, let range = record.sourceAnchor?.resolve(in: self.string) else { return }
                self.scrollRangeToVisible(range);self.setSelectedRange(range)
            }, anchorView: self, sourceAnchor: record.sourceAnchor, renderedAnchor: record.renderedAnchor,
            memoryID: id, dismiss: { [weak self] in self?.clearReferenceSelection(expected: range) }))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let range = selectedRange()
        let selected = range.length > 0 && NSMaxRange(range) <= (string as NSString).length
            ? (string as NSString).substring(with: range) : ""
        let title = selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Open Agent Chat" : "Ask About Selection"
        let item = NSMenuItem(title: CodexReference.localized(title),
                              action: #selector(referenceToCodex(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = selected
        menu.insertItem(.separator(), at: 0)
        menu.insertItem(item, at: 0)
        return menu
    }

    @objc private func referenceToCodex(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let range = selectedRange()
        let snapshot = string
        let line = (snapshot as NSString).substring(to: min(range.location, (snapshot as NSString).length))
            .components(separatedBy: "\n").count
        var actual = NSRange()
        let rect = firstRect(forCharacterRange: range, actualRange: &actual)
        onReferenceToCodex?(ReferenceSelection(text: text, location: "原文第 \(line) 行", screenRect: rect, reveal: { [weak self] in
            guard let self, self.string == snapshot else { NSSound.beep(); return }
            self.window?.makeKeyAndOrderFront(nil)
            self.setSelectedRange(range)
            self.scrollRangeToVisible(range)
            self.showFindIndicator(for: range)
        }, anchorView: self, sourceAnchor: CodexTextAnchor.capture(in: snapshot, range: range),
            memoryID: CodexMemoryStore.shared.records(for: memoryFileURL).first(where: { $0.sourceAnchor?.resolve(in: snapshot) == range })?.id,
            dismiss: { [weak self] in self?.clearReferenceSelection(expected: range) }))
    }


    override func paste(_ sender: Any?) {
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
           onPasteImage?(image) == true {
            return
        }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURLs(from: sender.draggingPasteboard).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageURLs(from: sender.draggingPasteboard).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = imageURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        return onInsertImages?(urls) == true
    }

    private func imageURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []).filter {
            NSImage(contentsOf: $0) != nil
        }
    }
}

private final class UserTrackingScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        DispatchQueue.main.async { [weak self] in self?.onUserScroll?() }
    }
}

private final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts: [Int] = [0]
    private var needsLineRebuild = true

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func invalidateLineNumbers() {
        needsLineRebuild = true
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        rebuildLineStartsIfNeeded(textView.string)

        NSColor.windowBackgroundColor.withAlphaComponent(0.25).setFill()
        rect.fill()

        let visible = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let startLine = lineIndex(containing: characterRange.location)
        let endCharacter = min((textView.string as NSString).length, characterRange.location + characterRange.length + 1)
        let endLine = lineIndex(containing: endCharacter)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        if textView.string.isEmpty {
            ("1" as NSString).draw(at: NSPoint(x: ruleThickness - 14, y: textView.textContainerInset.height - visible.minY),
                                   withAttributes: attributes)
            return
        }

        for line in startLine...min(endLine, lineStarts.count - 1) {
            let character = min(lineStarts[line], max(0, (textView.string as NSString).length - 1))
            let glyph = layoutManager.glyphIndexForCharacter(at: character)
            var lineRange = NSRange()
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &lineRange)
            let y = textView.textContainerOrigin.y + fragment.minY - visible.minY
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + max(0, (fragment.height - size.height) / 2)),
                       withAttributes: attributes)
        }
    }

    private func rebuildLineStartsIfNeeded(_ text: String) {
        guard needsLineRebuild else { return }
        needsLineRebuild = false
        lineStarts = [0]
        for (index, unit) in text.utf16.enumerated() where unit == 10 { lineStarts.append(index + 1) }
    }

    private func lineIndex(containing character: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= character { low = middle + 1 } else { high = middle }
        }
        return max(0, low - 1)
    }
}

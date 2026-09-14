import AppKit
import WebKit

@MainActor
final class Probe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var loaded = false
    var messages = 0
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded = true }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { messages += 1 }
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.prohibited)
    var reference = DocumentReference(text: "中文 👋\r\n\r\n# heading\n```swift\nx < y\n```",
                                      title: "ignored", fileURL: URL(fileURLWithPath: "/tmp/文档 one.md"))
    precondition(reference.markdown == "来自 Mirror 的文档引用（/tmp/文档 one.md）：\n\n> 中文 👋\n> \n> # heading\n> ```swift\n> x < y\n> ```\n\n")
    precondition(DocumentReference(text: "draft", title: "Untitled", fileURL: nil).markdown ==
                 "来自 Mirror 的文档引用（Untitled）：\n\n> draft\n\n")
    let testDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MirrorMemoryTests-" + UUID().uuidString)
    let suite = "MirrorMemoryTests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        try? FileManager.default.removeItem(at: testDirectory)
        defaults.removePersistentDomain(forName: suite)
    }
    let memoryURL = testDirectory.appendingPathComponent("conversations.json")
    let memory = CodexMemoryStore(url: memoryURL, defaults: defaults)
    let anchorText = "甲段 👋 重复内容，第一处。\n乙段 重复内容，第二处。"
    let occurrence = (anchorText as NSString).range(of: "重复内容", options: .backwards)
    let anchor = CodexTextAnchor.capture(in: anchorText, range: occurrence)!
    precondition(anchor.resolve(in: "新增一行\n" + anchorText)?.location == occurrence.location + ("新增一行\n" as NSString).length)
    precondition(anchor.resolve(in: "原文已删除") == nil)
    precondition(anchor.resolve(in: "甲段 👋 重复内容，第一处。") == nil, "Deleting a repeated quote must not move its marker to the other occurrence")
    let ambiguous = CodexTextAnchor(quote: "重复", prefix: "", suffix: "", offset: 0)
    precondition(ambiguous.resolve(in: "重复 重复") == nil)
    reference.selection = ReferenceSelection(text: reference.text, sourceAnchor: CodexTextAnchor.capture(in: reference.text,
        range: NSRange(location: 0, length: (reference.text as NSString).length)))
    let configuration = WKWebViewConfiguration()
    let probe = Probe()
    configuration.userContentController.add(probe, contentWorld: .defaultClient, name: "mirrorReference")
    configuration.userContentController.addUserScript(WKUserScript(source: CodexReference.previewScript,
        injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
    webView.navigationDelegate = probe
    webView.loadHTMLString("<article><p>中文 selection</p><p>second paragraph</p></article>", baseURL: nil)
    let deadline = Date().addingTimeInterval(20)
    while !probe.loaded && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(probe.loaded, "WebKit load timed out")
    var done = false
    Task { @MainActor in
        do {
        let result = try await webView.callAsyncJavaScript("""
        const button = document.querySelector('button');
        const initiallyHidden = !button.classList.contains('visible');
        const range = document.createRange();
        range.selectNodeContents(document.querySelector('article'));
        window.getSelection().removeAllRanges();
        window.getSelection().addRange(range);
        document.dispatchEvent(new Event('selectionchange'));
        const visible = button.classList.contains('visible');
        button.click();
        document.querySelector('article').innerHTML = '<p>Updated text</p>';
        window.getSelection().removeAllRanges();
        document.dispatchEvent(new Event('selectionchange'));
        return initiallyHidden && visible && !button.classList.contains('visible') && document.querySelector('button') === button;
        """, arguments: [:], in: nil, contentWorld: .defaultClient)
        precondition(result as? Bool == true, "Selection test failed")
        let endpointPosition = try await webView.callAsyncJavaScript("""
        const article=document.querySelector('article'), button=document.querySelector('.mirror-reference-action');
        article.style.cssText='width:180px;margin:24px;font:16px/24px monospace';
        article.innerHTML='<p>first line selects words</p><p>second paragraph wraps across several lines to verify the selection endpoint</p>';
        const first=article.firstChild.firstChild,last=article.lastChild.firstChild,selection=window.getSelection();
        function check(a,ao,f,fo) {
          selection.setBaseAndExtent(a,ao,f,fo);document.dispatchEvent(new Event('selectionchange'));
          const caret=document.createRange();caret.setStart(f,fo);caret.collapse(true);
          const r=caret.getBoundingClientRect();
          const x=Math.max(8,Math.min(r.left-12,innerWidth-button.offsetWidth-8));
          const y=Math.max(8,r.bottom+button.offsetHeight+16>innerHeight ? r.top-button.offsetHeight-8 : r.bottom+8);
          return button.classList.contains('visible') && Math.abs(parseFloat(button.style.left)-x)<1 && Math.abs(parseFloat(button.style.top)-y)<1;
        }
        const forward=check(first,2,last,last.length), backward=check(last,last.length,first,2);
        const sameLine=check(first,0,first,12) && check(first,12,first,0);
        article.style.marginLeft='520px';
        const rightEdge=check(first,0,first,12) && parseFloat(button.style.left)+button.offsetWidth<=innerWidth-8;
        article.style.cssText='width:180px;margin:420px 0 0 24px;font:16px/24px monospace';
        const bottomEdge=check(first,0,first,12);
        article.style.cssText='';window.getSelection().removeAllRanges();
        return forward && backward && sameLine && rightEdge && bottomEdge;
        """, arguments: [:], in: nil, contentWorld: .defaultClient)
        precondition(endpointPosition as? Bool == true, "Selection action must follow the drag endpoint in both directions and avoid viewport edges")

        let anchored = try await webView.callAsyncJavaScript("""
        document.querySelector('article').innerHTML = '<p data-source-line="0">Same words</p><p data-source-line="10">Same words</p>';
        const second = document.querySelectorAll('p')[1];
        const range = document.createRange();range.selectNodeContents(second);
        window.getSelection().removeAllRanges();window.getSelection().addRange(range);
        document.dispatchEvent(new Event('selectionchange'));
        const now = Date.now, random = Math.random;
        Date.now = () => 1234; Math.random = () => 0;
        document.querySelector('button').click();
        Date.now = now;Math.random = random;
        window.getSelection().removeAllRanges();
        window.mirrorRevealReference('1234-');
        const highlighted = window.CSS?.highlights?.get('mirror-reference');
        const restored = highlighted ? [...highlighted][0] : window.getSelection().getRangeAt(0);
        const correct = restored.startContainer === second && restored.toString() === 'Same words';
        second.remove();window.mirrorRevealReference('1234-');
        return correct;
        """, arguments: [:], in: nil, contentWorld: .defaultClient)
        precondition(anchored as? Bool == true, "Duplicate text must return to the selected occurrence")
        let memoryMarkers = try await webView.callAsyncJavaScript("""
        const article = document.querySelector('article');
        article.innerHTML='<p>First note</p><p>Remember me</p>';
        const saved = {id:'memory-test',preview:'My question',renderedAnchor:{quote:'Remember me',prefix:'First note',suffix:'',offset:10}};
        window.mirrorSetMemories([saved]);
        const count=()=>document.querySelectorAll('[aria-label^="回顾对话"]').length;
        if(count()!==1) return false;
        article.insertAdjacentHTML('afterbegin','<p>New heading</p>');
        window.mirrorSetMemories([saved]);
        if(count()!==1) return false;
        window.mirrorSetMemories([]);if(count()!==0) return false;
        const range=document.createRange();range.selectNodeContents(article.lastChild.firstChild);
        window.getSelection().removeAllRanges();window.getSelection().addRange(range);
        document.dispatchEvent(new Event('selectionchange'));
        const now=Date.now,random=Math.random;Date.now=()=>777;Math.random=()=>0;
        document.querySelector('.mirror-reference-action').click();Date.now=now;Math.random=random;
        window.mirrorClearReference('old-reference');if(!window.getSelection().toString())return false;
        window.mirrorClearReference('777-');
        return window.getSelection().toString()==='' && !window.CSS?.highlights?.has('mirror-reference');
        """, arguments: [:], in: nil, contentWorld: .defaultClient)
        precondition(memoryMarkers as? Bool == true, "Memory markers must survive inserted text, hide when disabled, and clear only their own selection")
        let highlightCleanup = try await webView.callAsyncJavaScript("""
        const article=document.querySelector('article');
        article.innerHTML='<ul data-source-line="0"><li>First item</li><li>Second item</li></ul>';
        const exact={id:'exact',preview:'question',renderedAnchor:{quote:'Second item',prefix:'First item',suffix:'',offset:10}};
        const fallback={id:'fallback',preview:'question',sourceLine:0,renderedAnchor:{quote:'missing source **markup**'}};
        const highlighted=()=>window.CSS?.highlights?.has('mirror-reference') || !!window.getSelection().toString();
        window.mirrorSetMemories([exact,fallback]);
        let scrollCalls=0;const originalScroll=Element.prototype.scrollIntoView;
        Element.prototype.scrollIntoView=function(){scrollCalls++;};
        window.mirrorRevealMemory('exact',false);
        window.mirrorRevealMemory('fallback',false);
        Element.prototype.scrollIntoView=originalScroll;
        if(scrollCalls!==0) return false;
        window.mirrorRevealMemory('exact');
        if(!highlighted()) return false;
        window.mirrorRevealMemory('fallback');if(highlighted()) return false;
        window.mirrorRevealMemory('exact');window.mirrorSetMemories([fallback]);if(highlighted()) return false;
        window.mirrorSetMemories([exact]);window.mirrorRevealMemory('exact');
        article.innerHTML='changed';window.mirrorRevealReference('exact');
        return !highlighted();
        """, arguments: [:], in: nil, contentWorld: .defaultClient)
        precondition(highlightCleanup as? Bool == true, "Block fallback, deleted records and invalid anchors must never leave reference highlights")
        precondition(probe.messages == 0, "Synthetic clicks must not trigger handoff")
        let exposed = try await webView.callAsyncJavaScript("return !!window.webkit?.messageHandlers?.mirrorReference;",
            arguments: [:], in: nil, contentWorld: .page)
        precondition(exposed as? Bool == false, "Bridge exposed to document")
        done = true
        } catch { fatalError("WebKit test failed: \(error)") }
    }
    while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(done, "Selection test timed out")
    configuration.userContentController.removeScriptMessageHandler(forName: "mirrorReference", contentWorld: .defaultClient)
    let desktop = CodexReference.desktopURL(prompt: "中文 & # + ?\n引用", directory: URL(fileURLWithPath: "/tmp/文档"))!
    let components = URLComponents(url: desktop, resolvingAgainstBaseURL: false)!
    precondition(components.queryItems?.first(where: { $0.name == "prompt" })?.value == "中文 & # + ?\n引用")
    precondition(CodexReference.desktopURL(prompt: "")?.absoluteString == "codex://threads/new")
    precondition(CodexReference.desktopURL(prompt: "draft", threadID: "thread-1")?.path == "/thread-1")
    var lifecycleDone = false
    Task { @MainActor in
        do {
            let server = CodexAppServer()
            let executable = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tools/CodexReferenceSmoke/fake-codex.py")
            try await server.connect(executable: executable)
            let model = CodexChatModel(reference: reference, directory: URL(fileURLWithPath: "/tmp"), server: server, memory: memory)
            precondition(model.messages.isEmpty && model.threadID == nil && model.reference != nil)
            var generationProfile = AgentProfile.preset(.codex)
            generationProfile.model = "fixture-model"; generationProfile.reasoningEffort = "high"
            model.selectAgent(generationProfile)
            model.draft = "Explain this"
            model.send()
            model.dismissFromUI()
            while model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
            precondition(model.error == nil, model.error ?? "")
            precondition(model.messages.count == 2 && model.messages[1].text == "已收到引用 👋")
            precondition(model.messages[0].text.contains(reference.markdown))
            precondition(model.reference == nil)
            model.saveMemory()
            precondition(memory.records.count == 1, "Submitted reference must create one memory")
            let saved = CodexMemoryStore(url: memoryURL, defaults: defaults).records.first!
            precondition(saved.threadID == nil && saved.messages.count == 2)
            let restored = CodexChatModel(reference: reference, directory: URL(fileURLWithPath: "/tmp"), memory: memory, restored: saved)
            precondition(restored.threadID == nil && restored.reference == nil && restored.messages.count == 2)
            restored.shutdown()
            memory.enabled = false
            precondition(memory.records(for: reference.fileURL).isEmpty)
            memory.save(CodexMemoryRecord(id: UUID(), filePath: "/tmp/disabled", title: "disabled", quote: "q", location: nil,
                sourceAnchor: nil, renderedAnchor: nil, threadID: nil, messages: [], updatedAt: Date()))
            precondition(memory.records.count == 1)
            memory.enabled = true
            precondition(memory.records(for: reference.fileURL).count == 1)
            let firstThread = model.threadID
            try await server.connect(executable: executable)
            model.draft = "Follow up"
            model.send()
            while model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
            precondition(model.threadID != nil && model.threadID != firstThread && model.messages.count == 4)
            precondition(model.messages.last?.text == "继续回答：上下文仍在")
            model.draft = "HOLD_TEST"
            model.send()
            try await Task.sleep(for: .milliseconds(100))
            model.stop()
            while model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
            precondition(model.status == "已停止")
            model.draft = "FAIL_TEST"
            model.send()
            while model.isRunning { try await Task.sleep(for: .milliseconds(10)) }
            precondition(model.draft == "FAIL_TEST" && model.error == "Simulated failure")
            model.shutdown()
            let blank = CodexChatModel(reference: nil, directory: URL(fileURLWithPath: "/tmp"))
            precondition(blank.reference == nil && blank.messages.isEmpty && blank.threadID == nil)
            precondition(!blank.canSend && blank.composedPrompt.isEmpty)
            blank.shutdown()
            try await server.connect(executable: executable)
            let pending = Task { try await server.request("test/pending", [:]) }
            try await Task.sleep(for: .milliseconds(20))
            server.close()
            do { _ = try await pending.value; fatalError("Close did not reject pending RPC") } catch { }
            lifecycleDone = true
        } catch { fatalError("Conversation test failed: \(error)") }
    }
    let lifecycleDeadline = Date().addingTimeInterval(25)
    while !lifecycleDone && Date() < lifecycleDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(lifecycleDone, "Conversation test timed out")
    if CommandLine.arguments.contains("--live") {
        var liveDone = false
        let live = CodexChatModel(reference: nil, directory: URL(fileURLWithPath: NSTemporaryDirectory()))
        live.draft = "This is a Mirror integration connectivity test. Do not use tools. Reply with only MIRROR_OK."
        live.send()
        let liveDeadline = Date().addingTimeInterval(90)
        while live.isRunning && Date() < liveDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        liveDone = !live.isRunning && live.error == nil && live.messages.contains { !$0.isUser && $0.text.contains("MIRROR_OK") }
        let liveError = live.error ?? (live.status.isEmpty ? "No expected reply received" : live.status)
        live.shutdown()
        if !liveDone { fputs("Live Codex test failed: \(liveError)\n", stderr); exit(1) }
        print("Live Codex account and streamed response passed")
    }
    if CommandLine.arguments.contains("--visual") {
        let preview = CodexChatPanel(reference: DocumentReference(text: "Mirror 将文件管理、源码编辑和实时预览整理在同一个轻量工作区中。", title: "产品介绍.md", fileURL: nil), directory: URL(fileURLWithPath: "/tmp"))
        preview.showWindow(nil)
        preview.model.draft = "帮我把这段介绍写得更简洁"
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let view = preview.window!.contentView!
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MirrorCodexReferenceSmoke/panel.png")
        try! bitmap.representation(using: .png, properties: [:])!.write(to: target)
        preview.close()
        print("Panel preview: \(target.path)")
    }
    print("Codex reference smoke passed: quotes, selection, isolated bridge, URL encoding, multi-turn streaming, empty chat, cancellation, errors, connection cleanup")
}

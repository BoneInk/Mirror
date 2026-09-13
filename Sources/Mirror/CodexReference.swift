import AppKit

struct ReferenceSelection {
    let text: String
    var location: String? = nil
    var screenRect: NSRect? = nil
    var reveal: (@MainActor () -> Void)? = nil
    weak var anchorView: NSView? = nil
    var sourceAnchor: CodexTextAnchor? = nil
    var renderedAnchor: CodexTextAnchor? = nil
    var memoryID: UUID? = nil
    var dismiss: (@MainActor () -> Void)? = nil
}

struct DocumentReference {
    let text: String
    let title: String
    let fileURL: URL?
    var selection: ReferenceSelection? = nil

    var markdown: String {
        let source = (fileURL?.path ?? title) + (selection?.location.map { " · " + $0 } ?? "")
        let quoted = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        return "来自 Mirror 的文档引用（\(source)）：\n\n\(quoted)\n\n"
    }
}

@MainActor
enum CodexReference {
    static func localized(_ key: String) -> String { AppLanguageStore().text(key) }

    static var previewScript: String {
        let title = CodexReference.localized("Ask Agent")
        let encoded = String(data: try! JSONEncoder().encode(title), encoding: .utf8)!
        return """
        (() => {
          const button = document.createElement('button');
          button.textContent = \(encoded);
          button.type = 'button';
          button.setAttribute('aria-label', \(encoded));
          const style = document.createElement('style');
          style.textContent = `
            .mirror-reference-action {position:fixed;z-index:2147483647;display:flex;align-items:center;gap:5px;padding:5px 9px;border:1px solid color-mix(in srgb,var(--fg) 12%,transparent);border-radius:8px;background:var(--bg);color:var(--fg);font:500 11px system-ui;line-height:16px;box-shadow:0 2px 8px #00000012;cursor:pointer;opacity:0;visibility:hidden;transform:translateY(-5px) scale(.96);transition:opacity .18s ease,transform .22s ease,visibility .18s;}
            .mirror-reference-action.visible {opacity:1;visibility:visible;transform:translateY(0) scale(1);}
            .mirror-reference-action:hover {background:var(--code);}
            .mirror-reference-action:focus-visible {outline:2px solid var(--accent);outline-offset:2px;}
            ::highlight(mirror-reference) {background:#dfac4055;color:inherit;}
            @media(prefers-reduced-motion:reduce) {.mirror-reference-action {transition:none;}}
          `;
          document.head.appendChild(style);
          const icon = document.createElementNS('http://www.w3.org/2000/svg','svg');
          icon.setAttribute('viewBox','0 0 16 16');icon.setAttribute('width','13');icon.setAttribute('height','13');icon.setAttribute('aria-hidden','true');
          const path=document.createElementNS('http://www.w3.org/2000/svg','path');
          path.setAttribute('d','M4 2.5h8a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2H7l-3.5 2v-2A2 2 0 0 1 2 9.5v-5a2 2 0 0 1 2-2Z');
          path.setAttribute('fill','none');path.setAttribute('stroke','currentColor');path.setAttribute('stroke-width','1.2');path.setAttribute('stroke-linejoin','round');icon.appendChild(path);button.prepend(icon);
          button.className = 'mirror-reference-action';
          document.body.appendChild(button);
          let selected = '', selectedRange = null;
          const references = new Map();
          let activeReferenceID = null;
          function textMap() {
            const article = document.querySelector('article');
            if (!article) return {text:'',nodes:[]};
            const walker = document.createTreeWalker(article, NodeFilter.SHOW_TEXT);
            let text = '', nodes = [], node;
            while (node = walker.nextNode()) {
              if (node.parentElement?.closest('button,script,style')) continue;
              nodes.push({node,offset:text.length});text += node.textContent;
            }
            return {text,nodes};
          }
          function anchorFor(range) {
            const map = textMap();
            const start = map.nodes.find(item => item.node === range.startContainer);
            if (!start) return null;
            const offset = start.offset + range.startOffset, quote = range.toString();
            return {quote,prefix:map.text.slice(Math.max(0,offset-48),offset),suffix:map.text.slice(offset+quote.length,offset+quote.length+48),offset,occurrenceCount:map.text.split(quote).length-1};
          }
          function resolveAnchor(anchor) {
            const map = textMap();
            if (!anchor?.quote) return null;
            let indexes=[],at=0;
            while ((at=map.text.indexOf(anchor.quote,at))>=0) {indexes.push(at);at+=anchor.quote.length;}
            if (indexes.length!==1 || (anchor.occurrenceCount || 1)>1) indexes=indexes.filter(i => (anchor.prefix || anchor.suffix) && map.text.slice(0,i).endsWith(anchor.prefix) && map.text.slice(i+anchor.quote.length).startsWith(anchor.suffix));
            if(indexes.length!==1) return null;
            const start=indexes[0],end=start+anchor.quote.length;
            const first=map.nodes.find(n=>n.offset+n.node.length>start),last=map.nodes.find(n=>n.offset+n.node.length>=end);
            if(!first || !last) return null;
            const range=document.createRange();range.setStart(first.node,start-first.offset);range.setEnd(last.node,end-last.offset);return range;
          }
          function sourceBlock(line) {
            const blocks=[...document.querySelectorAll('article > [data-source-line]')];
            return blocks.filter(b=>Number(b.dataset.sourceLine)<=line).sort((a,b)=>Number(b.dataset.sourceLine)-Number(a.dataset.sourceLine))[0];
          }
          let memories = [];
          const markers=document.createElement('div');document.body.appendChild(markers);
          function renderMemories() {
            markers.replaceChildren();
            const occupied=new Map();
            for(const memory of memories) {
              let range=resolveAnchor(memory.renderedAnchor);
              if(!range && memory.sourceLine != null) {
                const block=sourceBlock(memory.sourceLine);
                if(block) {range=document.createRange();range.selectNodeContents(block);}
              }
              if(!range) continue;
              const rect=range.getBoundingClientRect();
              const row=Math.round(rect.top+scrollY),existing=occupied.get(row);
              if(existing) {existing.ids.push(memory.id);existing.marker.title='回顾 '+existing.ids.length+' 条对话';continue;}
              const marker=document.createElement('button');marker.type='button';marker.appendChild(icon.cloneNode(true));
              marker.setAttribute('aria-label','回顾对话：'+memory.preview);
              marker.title='回顾对话：'+memory.preview;
              marker.style.cssText='position:absolute;z-index:20;width:24px;height:22px;padding:0;border:1px solid var(--line);border-radius:8px;background:var(--bg);color:var(--accent);cursor:pointer;font:700 12px system-ui';
              marker.style.top=(rect.top+scrollY)+'px';
              const article=document.querySelector('article').getBoundingClientRect();
              marker.style.left=Math.max(2,Math.min(innerWidth-28,article.left-30))+'px';
              const group={marker,ids:[memory.id]};occupied.set(row,group);
              marker.addEventListener('click',event=> {
                if(!event.isTrusted) return;
                references.set(memory.id,{range:range.cloneRange(),text:range.toString()});
                window.mirrorRevealReference(memory.id);
                const rect=range.getBoundingClientRect();
                window.webkit.messageHandlers.mirrorReference.postMessage({action:group.ids.length>1?'memoryMenu':'memory',id:memory.id,ids:group.ids,x:rect.x,y:rect.y,width:rect.width,height:rect.height});
              });
              marker.addEventListener('contextmenu',event=> {
                if(!event.isTrusted) return;
                event.preventDefault();event.stopPropagation();
                window.webkit.messageHandlers.mirrorReference.postMessage({action:'memoryContextMenu',ids:group.ids});
              });
              markers.appendChild(marker);
            }
          }
          window.mirrorRevealMemory = id => {
            const memory=memories.find(m=>m.id===id);
            if(!memory) return;
            let range=resolveAnchor(memory.renderedAnchor);
            if(!range && memory.sourceLine!=null) {
              const block=sourceBlock(memory.sourceLine);
              if(block) {range=document.createRange();range.selectNodeContents(block);}
            }
            if(range) {references.set(id,{range,text:range.toString()});window.mirrorRevealReference(id);}
          };
          window.mirrorSetMemories = values => {memories=values;renderMemories();};
          window.mirrorClearReference = id => {if(id && id !== activeReferenceID) return;activeReferenceID=null;window.getSelection()?.removeAllRanges();window.CSS?.highlights?.delete('mirror-reference');button.classList.remove('visible');};
          new ResizeObserver(renderMemories).observe(document.querySelector('article') || document.body);
          window.addEventListener('resize',renderMemories);

          window.mirrorRevealReference = id => {
            const saved = references.get(id), range = saved?.range;
            activeReferenceID = id;
            if (!range || !range.startContainer.isConnected || range.toString() !== saved.text) return;
            const element = range.startContainer.parentElement;
            element?.scrollIntoView({behavior:matchMedia('(prefers-reduced-motion:reduce)').matches?'auto':'smooth',block:'center'});
            if (window.CSS?.highlights) CSS.highlights.set('mirror-reference',new Highlight(range));
            else { const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range); }
          };
          // Selection.focus is the end of the user's drag, including backward selections.
          function selectionEndRect(selection, range) {
            if (!selection?.focusNode) return range.getBoundingClientRect();
            const caret = document.createRange();
            caret.setStart(selection.focusNode, selection.focusOffset);caret.collapse(true);
            const rect = caret.getBoundingClientRect();
            if (rect.height > 0) return rect;
            const rects = Array.from(range.getClientRects()).filter(r => r.height > 0);
            const backwards = selection.focusNode === range.startContainer && selection.focusOffset === range.startOffset;
            const edge = backwards ? rects[0] : rects[rects.length - 1];
            if (!edge) return range.getBoundingClientRect();
            return {x:backwards ? edge.left : edge.right,y:edge.top,left:backwards ? edge.left : edge.right,
                    top:edge.top,bottom:edge.bottom,width:1,height:edge.height};
          }
          function capture() {
            if (!selectedRange || !selected.trim()) return null;
            const id = String(Date.now()) + '-' + Math.random().toString(36).slice(2);
            activeReferenceID = id;
            for (const [key, saved] of references) if (!saved.range.startContainer.isConnected) references.delete(key);
            references.set(id, {range:selectedRange.cloneRange(),text:selected});
            const rect = selectionEndRect(window.getSelection(), selectedRange);
            let element = selectedRange.startContainer.nodeType === 1 ? selectedRange.startContainer : selectedRange.startContainer.parentElement;
            // Nested blockquotes render relative line numbers; use the outer source block.
            let source = element?.closest('[data-source-line]');
            while (source?.parentElement?.closest('[data-source-line]')) source = source.parentElement.closest('[data-source-line]');
            const line = source ? Number(source.dataset.sourceLine) + 1 : null;
            if (window.CSS?.highlights) CSS.highlights.set('mirror-reference',new Highlight(selectedRange.cloneRange()));
            return {action:'reference',text:selected,id,anchor:anchorFor(selectedRange),sourceLine:line ? line-1 : null,location:line ? '原文第 ' + line + ' 行所在段落' : '原文选区',x:rect.x,y:rect.y,width:rect.width,height:rect.height};
          }
          function update() {
            const selection = window.getSelection();
            selected = selection ? selection.toString() : '';
            if (!selected.trim() || !selection.rangeCount || button.contains(selection.anchorNode)) {
              button.classList.remove('visible'); return;
            }
            selectedRange = selection.getRangeAt(0).cloneRange();
            const rect = selectionEndRect(selection, selectedRange);
            if (rect.bottom < 0 || rect.top > innerHeight) { button.classList.remove('visible');return; }
            button.style.left = Math.max(8, Math.min(rect.left - 12, window.innerWidth - button.offsetWidth - 8)) + 'px';
            const top = rect.bottom + button.offsetHeight + 16 > innerHeight ? rect.top - button.offsetHeight - 8 : rect.bottom + 8;
            button.style.top = Math.max(8, top) + 'px';
            button.classList.add('visible');
          }
          document.addEventListener('contextmenu', event => {
            if (!event.isTrusted) return;
            event.preventDefault();
            window.webkit.messageHandlers.mirrorReference.postMessage({
              ...(capture() || {text:''}), action: 'contextMenu'
            });
          });
          document.addEventListener('selectionchange', update);
          document.addEventListener('pointerup', () => requestAnimationFrame(update));
          window.addEventListener('resize', update);
          window.addEventListener('scroll', update, true);
          button.addEventListener('mousedown', event => event.preventDefault());
          button.addEventListener('click', event => {
            const payload = capture();
            if (event.isTrusted && payload) window.webkit.messageHandlers.mirrorReference.postMessage(payload);
            button.classList.remove('visible');
          });
        })();
        """
    }

    static func send(selection: ReferenceSelection, title: String, fileURL: URL?, theme: EditorTheme = .paper) {
        let reference = selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : DocumentReference(text: selection.text, title: title, fileURL: fileURL, selection: selection)
        CodexChatPanel.open(reference: reference, theme: theme,
                            directory: fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser)
    }

    static func send(text: String, title: String, fileURL: URL?, theme: EditorTheme = .paper) {
        let reference = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : DocumentReference(text: text, title: title, fileURL: fileURL)
        CodexChatPanel.open(reference: reference, theme: theme,
                            directory: fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser)
    }

    static func desktopURL(prompt: String, threadID: String? = nil, directory: URL? = nil) -> URL? {
        var url = URLComponents()
        url.scheme = "codex"
        url.host = "threads"
        url.path = "/" + (threadID ?? "new")
        var items: [URLQueryItem] = []
        if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "prompt", value: prompt))
        }
        if threadID == nil, let directory { items.append(URLQueryItem(name: "path", value: directory.path)) }
        url.queryItems = items.isEmpty ? nil : items
        return url.url
    }

    static func openDesktop(prompt: String, threadID: String? = nil, directory: URL? = nil) -> Bool {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") != nil,
              let url = desktopURL(prompt: prompt, threadID: threadID, directory: directory) else { return false }
        return NSWorkspace.shared.open(url)
    }
}

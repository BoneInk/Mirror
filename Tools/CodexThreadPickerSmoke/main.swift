import AppKit
import SwiftUI

let firstID = "11111111-1111-4111-8111-111111111111"
let secondID = "22222222-2222-4222-8222-222222222222"
func row(_ id: String, name: String = "同名会话", ephemeral: Bool = false) -> [String: Any] {
    ["id": id, "name": name, "preview": "上下文预览 👋", "cwd": "/tmp/中文 project", "updatedAt": 1_700_000_000.0, "ephemeral": ephemeral]
}

NSApplication.shared.setActivationPolicy(.accessory)
Task { @MainActor in
    let quote = "中文 👋 & ? # % +\n```swift\nprint(\"quote\")\n```\n\n最后一行"
    let selection = ReferenceSelection(text: quote, location: "原文第 12 行", chooseCodexThread: true)
    let reference = DocumentReference(text: quote, title: "测试.md", fileURL: URL(fileURLWithPath: "/tmp/中文 project/测试.md"), selection: selection)
    if CommandLine.arguments.contains("--live") {
        let model = CodexThreadPickerModel(reference: reference)
        await model.load()
        precondition(model.error == nil, model.error ?? "")
        print("PASS: installed Codex app-server returned \(model.threads.count) real local threads; no threads resumed or modified")
        model.close(); exit(0)
    }
    if let index = CommandLine.arguments.firstIndex(of: "--handoff"), CommandLine.arguments.count > index + 1 {
        let id = CommandLine.arguments[index + 1]
        let model = CodexThreadPickerModel(reference: reference)
        await model.load()
        while !model.threads.contains(where: { $0.id == id }) && model.nextCursor != nil && model.error == nil { await model.load(more: true) }
        model.selectedID = id
        precondition(model.selected != nil, "Target not found in real list")
        await model.referenceSelection()
        precondition(model.error == nil && model.feedback != nil, model.error ?? "No handoff")
        print("PASS: OS accepted selected-thread handoff; verify draft in desktop before claiming receipt")
        model.close(); exit(0)
    }
    do {
        var calls: [(String, [String: Any])] = []
        var opened: [URL] = []
        var failList = false, failRead = false, failOpen = false
        let model = CodexThreadPickerModel(reference: reference, request: { method, params in
            calls.append((method, params))
            if method == "thread/list" {
                if failList { throw CodexConnectionError(message: "list failure") }
                if params["cursor"] != nil { return ["data": [row(firstID), row(secondID)], "nextCursor": NSNull()] }
                return ["data": [row(firstID), row(secondID, ephemeral: true)], "nextCursor": "page-2"]
            }
            precondition(method == "thread/read")
            precondition(params["includeTurns"] as? Bool == false)
            if failRead { throw CodexConnectionError(message: "target unavailable") }
            return ["thread": row(params["threadId"] as! String)]
        }, openURL: { url in opened.append(url); return !failOpen }, desktopAvailable: { true })
        await model.load()
        precondition(model.threads.count == 1 && model.selectedID == nil && !model.canReference)
        precondition(calls[0].1["sortKey"] as? String == "updated_at")
        precondition(calls[0].1["sourceKinds"] as? [String] == ["cli", "vscode", "appServer", "exec"])
        precondition(calls[0].1["cwd"] == nil, "Do not hide other projects")
        await model.load(more: true)
        precondition(model.threads.count == 2 && model.nextCursor == nil, "Pagination deduplicates IDs, not titles")
        model.search = "中文 project"; precondition(model.visibleThreads.count == 2)
        model.selectedID = firstID
        model.search = "no match"; precondition(model.visibleThreads.isEmpty && model.selectedID == nil && !model.canReference)
        model.search = ""
        model.selectedID = secondID
        failRead = true; await model.referenceSelection()
        precondition(model.error != nil && opened.isEmpty && model.reference.text == quote)
        failRead = false; failOpen = true; await model.referenceSelection()
        precondition(model.error != nil && model.feedback == nil && model.canReference)
        failOpen = false; await model.referenceSelection()
        precondition(model.feedback != nil && !model.canReference)
        let url = URLComponents(url: opened.last!, resolvingAgainstBaseURL: false)!
        precondition(url.host == "threads" && url.path == "/" + secondID)
        precondition(url.queryItems?.first(where: { $0.name == "prompt" })?.value == reference.markdown)
        precondition(reference.markdown.contains("/tmp/中文 project/测试.md · 原文第 12 行"))
        precondition(!calls.contains { ["thread/start", "thread/resume", "turn/start", "thread/inject_items"].contains($0.0) })
        let count = opened.count; await model.referenceSelection(); precondition(opened.count == count)
        failList = true; await model.load()
        precondition(model.error != nil && model.threads.isEmpty && model.selectedID == nil)
        failList = false; await model.load(); precondition(model.error == nil && model.threads.count == 1)
        model.close()
        let before = calls.count; await model.load(); precondition(calls.count == before)

        let empty = CodexThreadPickerModel(reference: reference, request: { _, _ in ["data": []] })
        await empty.load(); precondition(empty.threads.isEmpty && empty.error == nil && !empty.canReference); empty.close()
        let malformed = CodexThreadPickerModel(reference: reference, request: { _, _ in ["bad": []] })
        await malformed.load(); precondition(malformed.error != nil && !malformed.canReference); malformed.close()
        let missingApp = CodexThreadPickerModel(reference: reference, request: { _, _ in ["data": [row(firstID)]] },
            openURL: { _ in fatalError("Must not open without desktop") }, desktopAvailable: { false })
        await missingApp.load(); missingApp.selectedID = firstID; await missingApp.referenceSelection()
        precondition(missingApp.error != nil && missingApp.feedback == nil); missingApp.close()
        let large = DocumentReference(text: String(repeating: "中", count: 25000), title: "未保存.md", fileURL: nil)
        let oversized = CodexThreadPickerModel(reference: large, request: { method, _ in
            method == "thread/list" ? ["data": [row(firstID)]] : ["thread": row(firstID)]
        }, openURL: { _ in fatalError("Must not truncate or hand off oversized quotation") }, desktopAvailable: { true })
        await oversized.load(); oversized.selectedID = firstID; await oversized.referenceSelection()
        precondition(oversized.error?.contains("64 KB") == true && oversized.reference.text == large.text); oversized.close()

        var pending: CheckedContinuation<[String: Any], Error>?
        let delayed = CodexThreadPickerModel(reference: reference, request: { _, _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        })
        let task = Task { await delayed.load() }
        while pending == nil { await Task.yield() }
        precondition(delayed.loading)
        delayed.close(); pending?.resume(returning: ["data": [row(firstID)]])
        await task.value
        precondition(delayed.threads.isEmpty && !delayed.loading, "Closed panel ignores late responses")
        print("PASS: list, loading, empty, malformed, pagination, search, duplicate titles, exact target, Unicode/source, retry, failure, success, size bound, duplicate-click guard, close race")
        exit(0)
    }
}
NSApplication.shared.run()

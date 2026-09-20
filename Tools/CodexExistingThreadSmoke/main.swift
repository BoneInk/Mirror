import AppKit

NSApplication.shared.setActivationPolicy(.accessory)
Task { @MainActor in
    let id = "11111111-1111-4111-8111-111111111111"
    let thread = try! CodexThreadSummary(json: ["id": id, "name": "已有会话"])
    let reference = DocumentReference(text: "中文引用", title: "文档", fileURL: URL(fileURLWithPath: "/tmp/文档.md"), selection: ReferenceSelection(text: "中文引用", location: "第 1 行"))
    var desktop = true, failSend = false
    var calls: [String] = []
    var payloads: [String] = []
    let history: [String: Any] = ["thread": ["id": id, "turns": [["id": "old", "items": [
        ["id": "u0", "type": "userMessage", "content": [["type": "text", "text": "之前的问题"]]],
        ["id": "a0", "type": "agentMessage", "text": "之前的回答"]]]]]]
    let model = CodexExistingThreadModel(thread: thread, reference: reference, desktopRunning: { desktop }, request: { method, params in
        calls.append(method)
        precondition(params["threadId"] as? String == id)
        switch method {
        case "thread/read", "thread/resume": return history
        case "turn/start":
            payloads.append(((params["input"] as! [[String: Any]])[0]["text"] as! String))
            precondition(params["approvalPolicy"] as? String == "never")
            if failSend { throw CodexConnectionError(message: "模拟断线") }
            return ["turn": ["id": "new"]]
        case "turn/interrupt": return [:]
        default: fatalError("Unexpected mutation: \(method)")
        }
    })
    await model.load()
    precondition(model.messages.count == 2 && !model.needsReload)
    await model.send()
    precondition(calls == ["thread/read"] && model.error != nil && !model.draft.isEmpty)
    desktop = false
    await model.send()
    precondition(model.running && model.draft.isEmpty && payloads[0].contains("中文引用"))
    await model.send()
    precondition(payloads.count == 1)
    model.receive("item/agentMessage/delta", ["threadId": "other", "turnId": "new", "itemId": "a1", "delta": "错误"])
    precondition(model.messages.count == 2)
    model.receive("item/agentMessage/delta", ["threadId": id, "turnId": "new", "itemId": "a1", "delta": "新的回答"])
    precondition(model.messages.last?.text == "新的回答")
    await model.stop()
    precondition(calls.last == "turn/interrupt")
    model.receive("turn/completed", ["threadId": id, "turn": ["id": "new", "status": "interrupted"]])
    precondition(!model.running)
    model.draft = "继续"
    await model.send()
    precondition(payloads == [payloads[0], "继续"] && calls.filter { $0 == "thread/resume" }.count == 1)
    model.receive("turn/completed", ["threadId": id, "turn": ["id": "new", "status": "completed"]])
    failSend = true; model.draft = "未确认的问题"
    await model.send()
    precondition(model.needsReload && !model.running && model.draft == "未确认的问题")
    let count = payloads.count
    await model.send()
    precondition(payloads.count == count)
    await model.load()
    precondition(!model.needsReload && model.error?.contains("核对") == true)
    model.close()
    await model.send()
    precondition(payloads.count == count)
    print("PASS: history, exclusive desktop gate, same-thread multi-turn, streaming, interruption, uncertain-send recovery and disposal")
    exit(0)
}
RunLoop.main.run()

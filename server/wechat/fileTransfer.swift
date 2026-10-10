import AppKit
import ApplicationServices
import Foundation
import Vision

// This helper only sends to the currently open File Transfer Assistant chat.
// It fails closed when the target or the compose controls cannot be verified.

func result(_ ok: Bool, _ code: String, _ message: String, extra: [String: Any] = [:]) -> Never {
    var payload: [String: Any] = ["ok": ok, "code": code, "message": message]
    extra.forEach { payload[$0.key] = $0.value }
    if let data = try? JSONSerialization.data(withJSONObject: payload),
       let line = String(data: data, encoding: .utf8) {
        print(line)
    }
    exit(ok ? 0 : 1)
}

func attr(_ element: AXUIElement, _ name: CFString) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
}

func stringAttr(_ element: AXUIElement, _ name: CFString) -> String {
    attr(element, name) as? String ?? ""
}

func pointAttr(_ element: AXUIElement, _ name: CFString) -> CGPoint? {
    guard let value = attr(element, name) else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
}

func sizeAttr(_ element: AXUIElement, _ name: CFString) -> CGSize? {
    guard let value = attr(element, name) else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
}

func descendants(_ element: AXUIElement, depth: Int = 0) -> [AXUIElement] {
    if depth > 14 { return [] }
    let children = attr(element, kAXChildrenAttribute as CFString) as? [AXUIElement] ?? []
    return children.flatMap { [$0] + descendants($0, depth: depth + 1) }
}

func bounds(_ element: AXUIElement) -> CGRect? {
    guard let point = pointAttr(element, kAXPositionAttribute as CFString),
          let size = sizeAttr(element, kAXSizeAttribute as CFString) else { return nil }
    return CGRect(origin: point, size: size)
}

func click(_ point: CGPoint) {
    let location = CGPoint(x: point.x.rounded(), y: point.y.rounded())
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func key(_ code: CGKeyCode, command: Bool = false) {
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
    if command { down?.flags = .maskCommand; up?.flags = .maskCommand }
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

func pause(_ seconds: TimeInterval = 0.3) { Thread.sleep(forTimeInterval: seconds) }

let action = CommandLine.arguments.dropFirst().first ?? "status"
if action == "request-screen-recording" {
    let granted = CGRequestScreenCaptureAccess()
    result(granted, granted ? "READY" : "SCREEN_RECORDING_REQUIRED", granted ? "录屏权限已授权。" : "请在系统设置的隐私与安全性 > 录屏与系统录音中允许“终端”，然后重新启动小猫站点。")
}
if action == "request-permission" {
    let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    result(trusted, trusted ? "READY" : "ACCESSIBILITY_REQUIRED", trusted ? "辅助功能已授权。" : "请在系统设置的隐私与安全性 > 辅助功能中授权启动小猫站点的程序，然后返回页面重试。")
}
guard AXIsProcessTrusted() else {
    result(false, "ACCESSIBILITY_REQUIRED", "尚未获得 macOS 辅助功能权限。")
}
guard let wechat = NSRunningApplication.runningApplications(withBundleIdentifier: "com.tencent.xinWeChat").first else {
    result(false, "WECHAT_NOT_RUNNING", "请先打开并登录 Mac 微信。")
}
let app = AXUIElementCreateApplication(wechat.processIdentifier)

struct VisionText {
    let text: String
    let box: CGRect
}

func wechatWindow() -> (CGWindowID, CGRect)? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.compactMap { info -> (CGWindowID, CGRect)? in
        guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == wechat.processIdentifier,
              (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let rect = info[kCGWindowBounds as String] as? [String: NSNumber],
              let x = rect["X"]?.doubleValue, let y = rect["Y"]?.doubleValue,
              let width = rect["Width"]?.doubleValue, let height = rect["Height"]?.doubleValue,
              width >= 700, height >= 500 else { return nil }
        return (id, CGRect(x: x, y: y, width: width, height: height))
    }.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height })
}

func recognizeWindow() -> (CGRect, [VisionText])? {
    guard CGPreflightScreenCaptureAccess(), let (id, frame) = wechatWindow() else { return nil }
    let screenshot = FileManager.default.temporaryDirectory.appendingPathComponent("xhs-wechat-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: screenshot) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-l", String(id), screenshot.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run(); process.waitUntilExit() } catch { return nil }
    guard process.terminationStatus == 0 else { return nil }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false
    do { try VNImageRequestHandler(url: screenshot).perform([request]) } catch { return nil }
    let items = (request.results ?? []).compactMap { observation -> VisionText? in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        return VisionText(text: text, box: observation.boundingBox)
    }
    return (frame, items)
}

func visionTarget() -> (CGRect, [VisionText])? {
    guard let (frame, texts) = recognizeWindow() else { return nil }
    let titleFound = texts.contains { item in
        let compact = item.text.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return compact == "文件传输助手" && item.box.midX > 0.4 && item.box.midY > 0.88
    }
    return titleFound ? (frame, texts) : nil
}

func visionSendPoint(_ texts: [VisionText], in frame: CGRect) -> CGPoint? {
    guard let item = texts.filter({ item in
        item.text.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines) == "发送"
            && item.box.midX > 0.7 && item.box.midY < 0.25
    }).max(by: { $0.box.midX < $1.box.midX }) else { return nil }
    return CGPoint(x: frame.minX + frame.width * item.box.midX,
                   y: frame.minY + frame.height * (1 - item.box.midY))
}
func currentChat() -> (AXUIElement, CGRect, [AXUIElement])? {
    guard let windows = attr(app, kAXWindowsAttribute as CFString) as? [AXUIElement] else { return nil }
    for window in windows {
        guard let frame = bounds(window) else { continue }
        let nodes = descendants(window)
        let matchingTitle = nodes.contains { node in
            guard stringAttr(node, kAXRoleAttribute as CFString) == "AXStaticText",
                  let rect = bounds(node) else { return false }
            let labels = [stringAttr(node, kAXValueAttribute as CFString), stringAttr(node, kAXTitleAttribute as CFString)]
            return labels.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "文件传输助手" }
                && rect.midX > frame.minX + frame.width * 0.35
                && rect.midY < frame.minY + min(140, frame.height * 0.2)
        }
        if matchingTitle { return (window, frame, nodes) }
    }
    return nil
}

if action == "status" {
    if let (_, frame, nodes) = currentChat() {
        let composerVisible = nodes.contains { node in
            let role = stringAttr(node, kAXRoleAttribute as CFString)
            guard role == "AXTextArea" || role == "AXTextField", let rect = bounds(node) else { return false }
            return rect.midX > frame.minX + frame.width * 0.35 && rect.midY > frame.minY + frame.height * 0.65
        }
        if composerVisible { result(true, "READY", "已确认 Mac 微信的文件传输助手会话和输入框，可以发送。") }
    }
    guard CGPreflightScreenCaptureAccess() else {
        result(false, "SCREEN_RECORDING_REQUIRED", "当前微信版本未提供可读取的聊天控件。请允许终端录屏后，使用本机画面识别核对发送目标。")
    }
    guard visionTarget() != nil else {
        result(false, "TARGET_UNVERIFIED", "当前微信窗口顶部未识别到“文件传输助手”。请打开该会话后重新检查。")
    }
    result(true, "READY", "已从微信窗口识别到文件传输助手，可以发送。")
}

if action == "inspect" {
    guard let (_, frame, nodes) = currentChat() else {
        result(false, "TARGET_UNVERIFIED", "当前微信会话不是可验证的文件传输助手。")
    }
    let controls = nodes.compactMap { node -> [String: Any]? in
        let role = stringAttr(node, kAXRoleAttribute as CFString)
        guard ["AXTextArea", "AXTextField", "AXButton"].contains(role), let rect = bounds(node) else { return nil }
        return ["role": role, "title": stringAttr(node, kAXTitleAttribute as CFString), "x": Int(rect.midX), "y": Int(rect.midY)]
    }
    result(true, "TARGET_VERIFIED", "已识别文件传输助手会话。", extra: ["window": [Int(frame.minX), Int(frame.minY), Int(frame.width), Int(frame.height)], "controls": controls])
}
guard action == "send" else { result(false, "BAD_ACTION", "未知操作。") }
let data = FileHandle.standardInput.readDataToEndOfFile()
guard let input = try? JSONSerialization.jsonObject(with: data) as? [String: String],
      let text = input["text"], !text.isEmpty,
      let imagePath = input["imagePath"],
      let image = try? Data(contentsOf: URL(fileURLWithPath: imagePath)) else {
    result(false, "BAD_REQUEST", "缺少有效文案或 PNG 封面。")
}
if !wechat.isActive {
    wechat.activate(options: [.activateIgnoringOtherApps])
    pause(0.5)
}
guard wechat.isActive else {
    result(false, "WECHAT_NOT_FRONTMOST", "无法将 Mac 微信切换到前台，请手动打开文件传输助手会话。")
}

func sendWithVision(image: Data, text: String) -> Never {
    guard CGPreflightScreenCaptureAccess() else {
        result(false, "SCREEN_RECORDING_REQUIRED", "需要在系统设置中允许终端录屏，才能核对微信发送目标。")
    }
    guard let (frame, _) = visionTarget() else {
        result(false, "TARGET_UNVERIFIED", "微信窗口顶部未识别到“文件传输助手”，已停止发送。")
    }
    let pasteboard = NSPasteboard.general
    let originalItems = pasteboard.pasteboardItems ?? []
    func restore() {
        pasteboard.clearContents()
        if !originalItems.isEmpty { pasteboard.writeObjects(originalItems) }
    }
    let composer = CGPoint(x: frame.minX + frame.width * 0.68, y: frame.minY + frame.height * 0.85)
    click(composer)
    pause()
    pasteboard.clearContents()
    guard pasteboard.setData(image, forType: .png) else {
        restore()
        result(false, "IMAGE_CLIPBOARD_FAILED", "封面图未能放入剪贴板。")
    }
    key(9, command: true)
    pause(0.7)
    guard let (imageFrame, imageTexts) = visionTarget(), let imageSend = visionSendPoint(imageTexts, in: imageFrame) else {
        restore()
        result(false, "IMAGE_SEND_UNVERIFIED", "粘贴封面后无法核对微信的发送按钮；请检查图片是否停留在输入框。")
    }
    click(imageSend)
    pause(0.8)
    guard let (textFrame, _) = visionTarget() else {
        restore()
        result(false, "TEXT_SEND_UNVERIFIED", "封面图已交给微信，但会话随后无法核对；文案尚未发送。", extra: ["partial": true])
    }
    click(CGPoint(x: textFrame.minX + textFrame.width * 0.68, y: textFrame.minY + textFrame.height * 0.85))
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    key(9, command: true)
    pause(0.35)
    guard let (finalFrame, finalTexts) = visionTarget(), let textSend = visionSendPoint(finalTexts, in: finalFrame) else {
        restore()
        result(false, "TEXT_SEND_UNVERIFIED", "封面图已交给微信，但无法核对文案发送按钮；请在文件传输助手中检查。", extra: ["partial": true])
    }
    click(textSend)
    restore()
    result(true, "SENT", "已将封面图和文案交给微信文件传输助手。请在微信中确认两条消息。")
}

if currentChat() == nil { sendWithVision(image: image, text: text) }
guard let (_, frame, nodes) = currentChat() else {
    result(false, "TARGET_UNVERIFIED", "请先在 Mac 微信中打开文件传输助手会话，确认窗口顶部显示“文件传输助手”。")
}
guard let composer = nodes.first(where: { node in
    let role = stringAttr(node, kAXRoleAttribute as CFString)
    guard role == "AXTextArea" || role == "AXTextField", let rect = bounds(node) else { return false }
    return rect.midX > frame.minX + frame.width * 0.35 && rect.midY > frame.minY + frame.height * 0.65
}), let composerFrame = bounds(composer) else {
    result(false, "COMPOSER_UNVERIFIED", "未能识别微信的消息输入框，发送已停止。")
}

func sendButton() -> AXUIElement? {
    guard let (_, frame, nodes) = currentChat() else { return nil }
    return nodes.first { node in
        guard stringAttr(node, kAXRoleAttribute as CFString) == "AXButton", let rect = bounds(node) else { return false }
        let labels = [stringAttr(node, kAXTitleAttribute as CFString), stringAttr(node, kAXDescriptionAttribute as CFString), stringAttr(node, kAXValueAttribute as CFString)]
        return labels.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "发送" }
            && rect.midX > frame.minX + frame.width * 0.35 && rect.midY > frame.minY + frame.height * 0.65
    }
}

let pasteboard = NSPasteboard.general
let originalItems = pasteboard.pasteboardItems ?? []
func restorePasteboard() {
    pasteboard.clearContents()
    if !originalItems.isEmpty { pasteboard.writeObjects(originalItems) }
}

click(CGPoint(x: composerFrame.midX, y: composerFrame.midY))
pause()
pasteboard.clearContents()
guard pasteboard.setData(image, forType: .png) else { result(false, "IMAGE_CLIPBOARD_FAILED", "封面图未能放入剪贴板。") }
key(9, command: true) // Command-V
pause(0.7)
guard currentChat() != nil, let imageSend = sendButton(), AXUIElementPerformAction(imageSend, kAXPressAction as CFString) == .success else {
    restorePasteboard()
    result(false, "IMAGE_SEND_UNVERIFIED", "无法确认图片发送按钮；图片可能停留在输入框，请在微信中检查。")
}
pause(0.6)
guard let (_, nextFrame, nextNodes) = currentChat(),
      let nextComposer = nextNodes.first(where: { node in
          let role = stringAttr(node, kAXRoleAttribute as CFString)
          guard role == "AXTextArea" || role == "AXTextField", let rect = bounds(node) else { return false }
          return rect.midX > nextFrame.minX + nextFrame.width * 0.35 && rect.midY > nextFrame.minY + nextFrame.height * 0.65
      }), let nextComposerFrame = bounds(nextComposer) else {
    restorePasteboard()
    result(false, "TEXT_SEND_UNVERIFIED", "封面图已交给微信，但文案尚未发送。请在文件传输助手中检查。", extra: ["partial": true])
}
click(CGPoint(x: nextComposerFrame.midX, y: nextComposerFrame.midY))
pasteboard.clearContents()
pasteboard.setString(text, forType: .string)
key(9, command: true)
pause(0.3)
guard currentChat() != nil, let textSend = sendButton(), AXUIElementPerformAction(textSend, kAXPressAction as CFString) == .success else {
    restorePasteboard()
    result(false, "TEXT_SEND_UNVERIFIED", "封面图已交给微信，但文案可能停留在输入框。请在文件传输助手中检查。", extra: ["partial": true])
}
restorePasteboard()
result(true, "SENT", "已将封面图和文案交给微信文件传输助手。请在微信中确认两条消息。")

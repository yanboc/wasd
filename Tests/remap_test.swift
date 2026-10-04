import ApplicationServices
import Carbon.HIToolbox
import Cocoa

// 端到端验证工具：
// 1. 创建一个被动（listenOnly）事件 tap，追加在 tap 链尾部，观察被 WASD 改写之后的事件
// 2. 向系统注入合成按键事件（Caps 按下/抬起、A 按下/抬起、F13 按下/抬起）
// 3. 校验：Caps 事件被吞掉、Caps+A 变成 ←（123）、未映射的 F13 保持原样（105）

var recorded: [(CGEventType, Int64, CGEventFlags)] = []

func recordCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon _: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .keyDown || type == .keyUp || type == .flagsChanged {
        recorded.append((type, event.getIntegerValueField(.keyboardEventKeycode), event.flags))
    }
    return Unmanaged.passUnretained(event)
}

let mask: CGEventMask =
    (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

func axTrusted(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
}

func waitUntil(_ seconds: TimeInterval, _ message: String, _ ready: () -> Bool) {
    if ready() { return }
    print(message)
    fflush(stdout)
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if ready() {
            print("就绪")
            fflush(stdout)
            return
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.4))
    }
    FileHandle.standardError.write("超时：\(message)\n".data(using: .utf8)!)
    exit(1)
}

if !axTrusted(prompt: false) {
    print("""
    remap_test 还没有「辅助功能」权限。
    请打开「系统设置 → 隐私与安全性 → 辅助功能」，打开 remap_test 的开关。
    授权后测试会自己继续，最多等 90 秒。
    """)
    fflush(stdout)
    _ = axTrusted(prompt: true)
}
waitUntil(90, "仍在等待 remap_test 的辅助功能权限…") { axTrusted(prompt: false) }

waitUntil(90, """
WASD 还没开始监听键盘。
请为 WASD 打开两项开关：「辅助功能」和「输入监控」。
应用路径写在 WASD 的引导窗里。授权后测试会自己继续，最多等 90 秒。
""") {
    (try? String(contentsOfFile: "/tmp/wasd-test.log", encoding: .utf8))?.contains("键盘事件监听已启动") == true
}

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .tailAppendEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: recordCallback,
    userInfo: nil
) else {
    FileHandle.standardError.write("错误：无法创建监听 tap，本测试工具也需要辅助功能权限\n".data(using: .utf8)!)
    exit(1)
}
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

let src = CGEventSource(stateID: .hidSystemState)

print("3 秒后开始注入测试事件，请勿触碰键盘和鼠标…")
fflush(stdout)
sleep(3)

func postKey(_ keyCode: Int64, down: Bool, flags: CGEventFlags = [], wait: UInt32 = 150_000) {
    let event = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: down)!
    event.flags = flags
    event.post(tap: .cghidEventTap)
    usleep(wait)
}

func postFlags(_ keyCode: Int64, flags: CGEventFlags, wait: UInt32 = 80_000) {
    let event = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true)!
    event.type = .flagsChanged
    event.flags = flags
    event.post(tap: .cghidEventTap)
    usleep(wait)
}

func pump(_ seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
}

func inputSourceID(_ ref: TISInputSource) -> String? {
    guard let ptr = TISGetInputSourceProperty(ref, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

func currentInputSourceID() -> String? {
    guard let ref = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
    return inputSourceID(ref)
}

func selectInputSource(id: String) {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return }
    for index in 0 ..< CFArrayGetCount(list) {
        guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
        let ref = Unmanaged<TISInputSource>.fromOpaque(raw).takeUnretainedValue()
        if inputSourceID(ref) == id {
            TISSelectInputSource(ref)
            return
        }
    }
}

func hasBothChineseAndEnglish() -> Bool {
    guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return false }
    var chinese = false
    var english = false
    for index in 0 ..< CFArrayGetCount(list) {
        guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
        let ref = Unmanaged<TISInputSource>.fromOpaque(raw).takeUnretainedValue()
        guard let ptr = TISGetInputSourceProperty(ref, kTISPropertyInputSourceLanguages) else { continue }
        let languages = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String] ?? []
        if languages.first?.hasPrefix("zh") == true { chinese = true }
        if languages.first?.hasPrefix("en") == true { english = true }
    }
    return chinese && english
}

func capsStateOn() -> Bool {
    CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
}

let capsBefore = capsStateOn()

postKey(57, down: true, flags: .maskAlphaShift) // Caps 按下
postKey(0, down: true) // Caps+A 按下  -> 期望改写为 ← (123)
postKey(0, down: false) // Caps+A 抬起 -> 期望改写为 ← (123)
postKey(57, down: false, flags: []) // Caps 抬起
postKey(105, down: true) // 单独 F13 按下 -> 期望原样 (105)
postKey(105, down: false)
pump(0.6)
let capsRecord = recorded

let sourceBeforeTap = currentInputSourceID()
let tapStart = recorded.count
postFlags(56, flags: .maskShift) // 短按 Shift 按下
postFlags(56, flags: []) // 短按 Shift 抬起
pump(0.5)
let sourceAfterTap = currentInputSourceID()
if let sourceBeforeTap { selectInputSource(id: sourceBeforeTap) }
pump(0.2)

let chordStart = recorded.count
let sourceBeforeChord = currentInputSourceID()
postFlags(56, flags: .maskShift, wait: 60_000)
postKey(111, down: true, wait: 60_000) // Shift+F12，应保持修饰、不切换输入源
postKey(111, down: false, wait: 60_000)
postFlags(56, flags: [])
pump(0.5)
let sourceAfterChord = currentInputSourceID()
if let sourceBeforeChord { selectInputSource(id: sourceBeforeChord) }

print("\n=== 捕获到的事件 ===")
for (type, keyCode, flags) in recorded {
    let name = type == .keyDown ? "keyDown " : type == .keyUp ? "keyUp   " : "flagsCh "
    print("\(name) keyCode=\(keyCode) flags=0x\(String(flags.rawValue, radix: 16))")
}

var pass = true
func check(_ cond: Bool, _ msg: String) {
    print("\(cond ? "PASS" : "FAIL"): \(msg)")
    if !cond { pass = false }
}

let capsEvents = capsRecord.filter { $0.1 == 57 }
let aDown = capsRecord.first { $0.0 == .keyDown && $0.1 != 105 }
let aUp = capsRecord.first { $0.0 == .keyUp && $0.1 != 105 }
let f13 = capsRecord.filter { $0.1 == 105 }
let tapEvents = recorded[tapStart...]
let chordEvents = recorded[chordStart...]
let tapShift = tapEvents.filter { $0.1 == 56 || $0.1 == 60 }
let f12Down = chordEvents.first { $0.0 == .keyDown && $0.1 == 111 }

check(capsEvents.isEmpty, "Caps Lock 事件被吞掉（未观察到 keyCode 57）")
check(aDown?.1 == 123, "Caps+A 按下被改写为 ←（keyCode 123），实际：\(aDown?.1 ?? -1)")
check(aUp?.1 == 123, "Caps+A 抬起被改写为 ←（keyCode 123），实际：\(aUp?.1 ?? -1)")
check(f13.count == 2, "未映射键 F13 原样透传（down+up 共 2 个事件），实际：\(f13.count)")
check(capsStateOn() == capsBefore, "测试前后系统大写锁定状态未变化（\(capsBefore) -> \(capsStateOn())）")
check(tapShift.isEmpty, "短按 Shift 被吞掉（未观察到 keyCode 56/60），实际：\(tapShift.count)")
if hasBothChineseAndEnglish() {
    check(sourceBeforeTap != sourceAfterTap, "短按 Shift 切换了输入源（\(sourceBeforeTap ?? "nil") -> \(sourceAfterTap ?? "nil")）")
} else {
    print("SKIP: 系统里没有同时启用的中文和英文输入源，不断言切换结果")
}
check(f12Down?.2.contains(.maskShift) == true, "Shift+F12 仍带 Shift 修饰")
check(sourceBeforeChord == sourceAfterChord, "Shift 组合键不切换输入源（\(sourceBeforeChord ?? "nil") -> \(sourceAfterChord ?? "nil")）")

print(pass ? "\n全部通过 ✅" : "\n存在失败项 ❌")
exit(pass ? 0 : 1)

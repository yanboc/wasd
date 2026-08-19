import ApplicationServices
import Cocoa

// 键盘事件记录仪：被动监听所有按键事件并打印，用于诊断物理 Caps Lock 的真实事件序列。
// 用法：先退出 CapsJ4Mac，再运行本工具，操作键盘后查看输出。

func logCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon _: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
        return Unmanaged.passUnretained(event)
    }
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let name = type == .keyDown ? "keyDown " : type == .keyUp ? "keyUp   " : "flagsCh "
    let capsState = CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift) ? "ON " : "off"
    let line = String(format: "%@ keyCode=%3lld flags=0x%llx capsLockState=%@", name, keyCode, event.flags.rawValue, capsState)
    FileHandle.standardOutput.write((line + "\n").data(using: .utf8)!)
    return Unmanaged.passUnretained(event)
}

let mask: CGEventMask =
    (CGEventMask(1) << CGEventType.keyDown.rawValue)
        | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .tailAppendEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: logCallback,
    userInfo: nil
) else {
    FileHandle.standardError.write("错误：无法创建监听 tap（需要辅助功能权限）\n".data(using: .utf8)!)
    exit(1)
}
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
FileHandle.standardOutput.write("记录中…\n".data(using: .utf8)!)
CFRunLoopRun()

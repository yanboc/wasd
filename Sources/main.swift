import ApplicationServices
import Cocoa
import IOKit.hid

// MARK: - 映射表

/// Caps Lock 的虚拟键码
private let capsLockKeyCode: Int64 = 57

/// 按住 Caps 期间的映射表：物理键码 -> 目标键码
private let keyMap: [Int64: Int64] = [
    0: 123, // A -> ←
    1: 125, // S -> ↓
    2: 124, // D -> →
    13: 126, // W -> ↑
    33: 115, // [ -> Home
    30: 119, // ] -> End
]

// MARK: - 核心状态

final class RemapController {
    static let shared = RemapController()

    /// 映射是否启用（菜单可暂停/恢复）
    var enabled = true
    /// Caps Lock 当前是否被物理按住（由 IOHIDManager 提供；CGEvent 层的 Caps 是切换式信号，无抬起事件，不可用）
    var capsHeld = false
    /// 已按下且被映射的物理键集合：保证抬起事件仍发改写后的键码，即使 Caps 已先松开
    var activeMappedKeys = Set<Int64>()
    /// 键盘事件 tap
    var eventTap: CFMachPort?
    /// HID 层 Caps 物理状态监听
    var hidManager: IOHIDManager?

    func resetState() {
        capsHeld = false
        activeMappedKeys.removeAll()
    }
}

// MARK: - 事件 tap 回调

private func eventTapCallback(
    proxy _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon _: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let controller = RemapController.shared

    // 系统因超时等原因禁用 tap 时立即重新启用
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = controller.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    // 暂停状态：一切按键（含 Caps 原生大写锁定）原样放行
    guard controller.enabled else {
        controller.resetState()
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    if type == .flagsChanged {
        // Caps Lock：CGEvent 层的物理 Caps 是"切换式"信号——每次按下只发一个事件、
        // 交替翻转 maskAlphaShift，抬起时不发事件，无法据此跟踪按住状态（实测确认）。
        // 按住状态由 IOHIDManager 提供；这里只吞掉事件并复位驱动层的大写锁定。
        if keyCode == capsLockKeyCode {
            if ProcessInfo.processInfo.environment["CAPSJ4MAC_TAP_STATE"] == "1" {
                // 仅供自动化测试（合成事件不经过 HID 层）：CAPSJ4MAC_TAP_STATE=1 时由 tap 代管状态
                controller.capsHeld = event.flags.contains(.maskAlphaShift)
            }
            clearCapsLockState()
            return nil
        }
        // Shift 等其他修饰键透传
        return Unmanaged.passUnretained(event)
    }

    // Caps 按住期间剥离大写标记，防止 HID 层锁定状态把字母大写化
    if controller.capsHeld, event.flags.contains(.maskAlphaShift) {
        var flags = event.flags
        flags.remove(.maskAlphaShift)
        event.flags = flags
    }

    // 按下：Caps 按住且命中映射表 -> 改写键码（修饰键 flags 原样保留）
    if type == .keyDown, controller.capsHeld, let mapped = keyMap[keyCode] {
        event.setIntegerValueField(.keyboardEventKeycode, value: mapped)
        controller.activeMappedKeys.insert(keyCode)
        return Unmanaged.passUnretained(event)
    }

    // 抬起：凡被映射过的键，抬起也发改写后的键码（即使 Caps 已先松开）
    if type == .keyUp, controller.activeMappedKeys.contains(keyCode), let mapped = keyMap[keyCode] {
        event.setIntegerValueField(.keyboardEventKeycode, value: mapped)
        controller.activeMappedKeys.remove(keyCode)
        return Unmanaged.passUnretained(event)
    }

    return Unmanaged.passUnretained(event)
}

private func setupEventTap() -> Bool {
    guard RemapController.shared.eventTap == nil else { return true }

    let mask: CGEventMask =
        (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)

    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: eventTapCallback,
        userInfo: nil
    ) else {
        return false
    }

    RemapController.shared.eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
}

/// 用 IOHIDManager 监听 Caps Lock 的物理按下/抬起（HID 层有真实的 press/release，
/// 与 CGEvent 层的切换式信号不同）。需要"输入监控"权限。
private func setupCapsPhysicalMonitor() {
    guard RemapController.shared.hidManager == nil else { return }

    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
        kIOHIDDeviceUsagePageKey: 0x01, // Generic Desktop
        kIOHIDDeviceUsageKey: 0x06, // Keyboard
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
        let element = IOHIDValueGetElement(value)
        // Keyboard/Keypad usage page (0x07) 上的 Caps Lock (0x39)
        guard IOHIDElementGetUsagePage(element) == 0x07,
              IOHIDElementGetUsage(element) == 0x39
        else { return }
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        RemapController.shared.capsHeld = pressed
    }, nil)
    IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if result != kIOReturnSuccess {
        log("IOHIDManager 打开失败（需要输入监控权限）: \(result)")
    } else {
        RemapController.shared.hidManager = manager
        log("Caps 物理状态监听已启动")
    }
}

private func log(_ message: String) {
    FileHandle.standardError.write(("[CapsJ4Mac] \(message)\n").data(using: .utf8)!)
}

// MARK: - 菜单栏 App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_: Notification) {
        setupStatusItem()
        ensurePermissionThenStart()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "CapsJ4Mac")
            button.image?.isTemplate = true
            button.toolTip = "CapsJ4Mac"
        }

        let menu = NSMenu()
        statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        toggleMenuItem = NSMenuItem(title: "", action: #selector(toggleRemapping), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 CapsJ4Mac", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private static let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

    private func isTrusted() -> Bool {
        AXIsProcessTrustedWithOptions([Self.promptKey: false] as CFDictionary)
    }

    private func ensurePermissionThenStart() {
        // IOHIDManager 监听需要"输入监控"权限，未授权时触发系统弹窗
        if !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            log("等待输入监控授权（系统设置 -> 隐私与安全性 -> 输入监控）")
        }
        // 首次启动触发辅助功能授权弹窗
        if AXIsProcessTrustedWithOptions([Self.promptKey: true] as CFDictionary) {
            startTap()
        } else {
            log("等待辅助功能授权（系统设置 -> 隐私与安全性 -> 辅助功能）")
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                guard let self, isTrusted() else { return }
                timer.invalidate()
                permissionTimer = nil
                startTap()
            }
        }
        updateUI()
    }

    private func startTap() {
        if setupEventTap() {
            clearCapsLockState()
            setupCapsPhysicalMonitor()
            log("键盘事件监听已启动")
        } else {
            log("事件监听创建失败，5 秒后重试")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.startTap()
            }
        }
        updateUI()
    }

    private func updateUI() {
        let controller = RemapController.shared
        if !isTrusted() {
            statusMenuItem.title = "状态：等待辅助功能授权…"
            toggleMenuItem.isEnabled = false
            statusItem.button?.alphaValue = 0.35
        } else if controller.enabled {
            statusMenuItem.title = "状态：映射中（Caps+WASD/[/]）"
            toggleMenuItem.title = "暂停映射"
            toggleMenuItem.isEnabled = true
            statusItem.button?.alphaValue = 1.0
        } else {
            statusMenuItem.title = "状态：已暂停"
            toggleMenuItem.title = "恢复映射"
            toggleMenuItem.isEnabled = true
            statusItem.button?.alphaValue = 0.35
        }
    }

    @objc private func toggleRemapping() {
        let controller = RemapController.shared
        controller.enabled.toggle()
        controller.resetState()
        if controller.enabled {
            // 暂停期间 Caps 恢复原生行为可能已锁定大写，恢复映射时强制复位
            clearCapsLockState()
        }
        updateUI()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - 入口

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

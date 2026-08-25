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

/// 辅助功能权限查询的 prompt 选项键
private let axPromptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String

// MARK: - 核心状态

final class RemapController {
    static let shared = RemapController()

    /// 映射是否启用（菜单可暂停/恢复）
    var enabled = true
    /// Caps Lock 当前是否被物理按住（由 IOHIDManager 提供；CGEvent 层的 Caps 是切换式信号，
    /// keyState 查询到的也是锁定切换状态而非物理按住（实测确认），均无法跟踪按住状态）
    var capsHeld = false
    /// 已按下且被映射的物理键集合：保证抬起事件仍发改写后的键码，即使 Caps 已先松开
    var activeMappedKeys = Set<Int64>()
    /// 键盘事件 tap
    var eventTap: CFMachPort?
    /// tap 对应的 runloop source（重建 tap 时需一并移除）
    var eventTapSource: CFRunLoopSource?
    /// HID 层 Caps 物理状态监听
    var hidManager: IOHIDManager?
    /// 诊断计数：tap 收到的键盘事件数（0 说明 tap 是"死"的）
    var tapEventsSeen = 0
    /// 诊断计数：tap 收到的 Caps flagsChanged 数
    var capsFlagsSeen = 0
    /// 诊断计数：HID 层上报的 Caps 物理事件数（0 说明 IOHIDManager 未投递回调）
    var hidEventsSeen = 0
    /// 诊断计数：HID 层上报的任意键盘事件数（>0 而 tapEventsSeen==0 说明 tap 是"死"的）
    var hidAnyEventsSeen = 0

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

    // 系统因超时等原因禁用 tap 时先原地恢复，失败则整体重建
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        let reason = type == .tapDisabledByTimeout ? "超时" : "用户输入"
        log("事件 tap 被系统禁用（\(reason)）")
        if let tap = controller.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                return Unmanaged.passUnretained(event)
            }
        }
        log("原地恢复失败，重建事件 tap")
        rebuildEventTap()
        return Unmanaged.passUnretained(event)
    }

    // 统计真实键盘事件流量，供看门狗识别"死 tap"
    if type == .keyDown || type == .keyUp || type == .flagsChanged {
        controller.tapEventsSeen += 1
        if controller.tapEventsSeen == 1 {
            log("事件 tap 收到首个键盘事件")
        }
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
            controller.capsFlagsSeen += 1
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
    RemapController.shared.eventTapSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    log("键盘事件 tap 已创建")
    return true
}

private func teardownEventTap() {
    let controller = RemapController.shared
    if let tap = controller.eventTap {
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = controller.eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
    }
    controller.eventTap = nil
    controller.eventTapSource = nil
    controller.resetState()
}

/// 销毁并重建事件 tap，供 tap 恢复失败、看门狗与系统通知共用
private func rebuildEventTap() {
    teardownEventTap()
    if !setupEventTap() {
        log("事件 tap 重建失败，5 秒后重试")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            rebuildEventTap()
        }
    }
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
        let controller = RemapController.shared
        controller.hidAnyEventsSeen += 1
        // Keyboard/Keypad usage page (0x07) 上的 Caps Lock (0x39)
        guard IOHIDElementGetUsagePage(element) == 0x07,
              IOHIDElementGetUsage(element) == 0x39
        else { return }
        let pressed = IOHIDValueGetIntegerValue(value) != 0
        controller.hidEventsSeen += 1
        if controller.hidEventsSeen == 1 {
            log("HID 层收到首个 Caps 物理事件")
        }
        controller.capsHeld = pressed
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

private func teardownCapsPhysicalMonitor() {
    let controller = RemapController.shared
    if let manager = controller.hidManager {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    controller.hidManager = nil
    controller.capsHeld = false
}

/// 关闭并重开 IOHIDManager，供看门狗与系统通知共用
private func reopenCapsPhysicalMonitor() {
    teardownCapsPhysicalMonitor()
    setupCapsPhysicalMonitor()
}

/// "输入监控"权限是否已授予
private func hasInputMonitoringAccess() -> Bool {
    IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
}

// MARK: - 日志

/// 日志同时写 stderr 与 ~/Library/Logs/CapsJ4Mac.log；
/// 登录项启动时 stderr 无处可去，文件日志是排查自启问题的唯一途径。
private let logURL: URL = {
    let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("CapsJ4Mac.log")
}()

private let logDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()

private func log(_ message: String) {
    let line = "[\(logDateFormatter.string(from: Date()))] \(message)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
    guard let data = line.data(using: .utf8) else { return }
    // 超过 256KB 重新开始，避免无限增长
    if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
       let size = attrs[.size] as? Int, size > 256 * 1024 {
        try? FileManager.default.removeItem(at: logURL)
    }
    if let handle = try? FileHandle(forWritingTo: logURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: logURL)
    }
}

// MARK: - 权限引导窗

/// 一键授权引导：每项权限一个按钮，点击触发系统授权弹窗并直达对应设置页面；
/// 每秒轮询授权状态并实时打勾，全部授予后自动开始工作并关窗。
final class PermissionGuideWindowController: NSWindowController, NSWindowDelegate {
    private let axStatus = NSTextField(labelWithString: "")
    private let imStatus = NSTextField(labelWithString: "")
    private let axButton = NSButton(title: "去授权", target: nil, action: nil)
    private let imButton = NSButton(title: "去授权", target: nil, action: nil)
    private let doneLabel = NSTextField(labelWithString: "")
    private var pollTimer: Timer?
    /// 两项权限全部授予后回调（启动事件监听）
    var onAllGranted: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "欢迎使用 CapsJ4Mac"
        window.center()
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("不支持 nib 初始化") }

    private func permissionRow(title: String, detail: String, status: NSTextField, button: NSButton, action: Selector) -> NSStackView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 13)

        let texts = NSStackView(views: [titleLabel, detailLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2

        button.bezelStyle = .rounded
        button.target = self
        button.action = action

        let row = NSStackView(views: [status, texts, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "需要两项权限，各点一次即可")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        let descLabel = NSTextField(wrappingLabelWithString:
            "点击每项右侧的“去授权”，系统会弹出授权请求并可直接跳转到对应设置页，打开 CapsJ4Mac 的开关即可。授权只需这一次，之后重启、升级都有效。")
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor

        let axRow = permissionRow(title: "辅助功能", detail: "拦截并改写键盘事件",
                                  status: axStatus, button: axButton, action: #selector(grantAccessibility))
        let imRow = permissionRow(title: "输入监控", detail: "监听 Caps 键的物理按下/抬起",
                                  status: imStatus, button: imButton, action: #selector(grantInputMonitoring))

        doneLabel.font = .systemFont(ofSize: 12)
        doneLabel.alignment = .center

        let stack = NSStackView(views: [titleLabel, descLabel, axRow, imRow, doneLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
            descLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            axRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            imRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
        ])
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // LSUIElement 应用默认不前置，需主动激活
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
        refreshStatus()
    }

    @objc private func grantAccessibility() {
        // 触发系统授权弹窗（自带"打开系统设置"直达按钮）
        _ = AXIsProcessTrustedWithOptions([axPromptKey: true] as CFDictionary)
        openSettingsPane("Privacy_Accessibility")
    }

    @objc private func grantInputMonitoring() {
        // 触发系统授权弹窗（未授权时弹出一次）
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openSettingsPane("Privacy_ListenEvent")
    }

    private func openSettingsPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    private func markGranted(_ status: NSTextField, _ button: NSButton, _ granted: Bool) {
        status.stringValue = granted ? "✅" : "⬜️"
        button.isEnabled = !granted
        button.title = granted ? "已授权" : "去授权"
    }

    private func refreshStatus() {
        let axGranted = AXIsProcessTrustedWithOptions([axPromptKey: false] as CFDictionary)
        let imGranted = hasInputMonitoringAccess()
        markGranted(axStatus, axButton, axGranted)
        markGranted(imStatus, imButton, imGranted)

        if axGranted, imGranted {
            doneLabel.stringValue = "✓ 两项权限均已授予，即将开始…"
            doneLabel.textColor = .systemGreen
            pollTimer?.invalidate()
            pollTimer = nil
            log("辅助功能与输入监控权限均已授予")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                close()
                onAllGranted?()
            }
        }
    }

    func windowWillClose(_: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

// MARK: - 菜单栏 App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var watchdogTimer: Timer?
    private var permissionGuide: PermissionGuideWindowController?
    private let launchedAt = Date()
    private var lastRebuildAt = Date.distantPast

    func applicationDidFinishLaunching(_: Notification) {
        log("应用启动（登录项启动时 stderr 不可见，完整日志见 ~/Library/Logs/CapsJ4Mac.log）")
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(sessionBecameActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
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

        let permissionItem = NSMenuItem(title: "权限设置…", action: #selector(openPermissionGuide), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 CapsJ4Mac", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func isTrusted() -> Bool {
        AXIsProcessTrustedWithOptions([axPromptKey: false] as CFDictionary)
    }

    private func hasAllPermissions() -> Bool {
        isTrusted() && hasInputMonitoringAccess()
    }

    private func ensurePermissionThenStart() {
        if hasAllPermissions() {
            startTap()
        } else {
            log("权限未齐备，显示一键授权引导窗")
            showPermissionGuide()
        }
        updateUI()
    }

    private func showPermissionGuide() {
        if permissionGuide == nil {
            permissionGuide = PermissionGuideWindowController()
            permissionGuide?.onAllGranted = { [weak self] in
                self?.permissionGuide = nil
                self?.startTap()
            }
        }
        permissionGuide?.show()
    }

    @objc private func openPermissionGuide() {
        showPermissionGuide()
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
        startWatchdog()
        updateUI()
    }

    // MARK: 看门狗：识别登录早期启动造成的静默失效

    private func startWatchdog() {
        guard watchdogTimer == nil else { return }
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkInputPipeline()
        }
    }

    /// 登录项启动时系统会话尚未就绪，可能创建出"死 tap"（创建成功但收不到事件），
    /// 或打开一个不投递回调的 IOHIDManager（capsHeld 永远为 false）。两类问题都表现为
    /// "图标显示映射中但实际不生效，手动重开应用后恢复"，这里检测并自动重建。
    /// 死 tap 判定采用确证式：HID 层已看到物理键盘活动而 tap 零事件，才是真的死了——
    /// 用户 idle 不敲键盘时不会误触发。
    private func checkInputPipeline() {
        let controller = RemapController.shared
        guard hasAllPermissions(), controller.eventTap != nil else { return }
        guard Date().timeIntervalSince(lastRebuildAt) > 30 else { return }

        // HID 层有真实键盘活动、tap 却零事件 -> 死 tap，重建（启动 10 秒后开始判定）
        if Date().timeIntervalSince(launchedAt) > 10,
           controller.hidAnyEventsSeen > 0, controller.tapEventsSeen == 0 {
            log("看门狗：HID 有键盘活动但 tap 无事件流入，判定为死 tap，重建")
            lastRebuildAt = Date()
            rebuildEventTap()
            return
        }

        // tap 能看到 Caps 的 flagsChanged，HID 层却从未上报物理事件
        // -> IOHIDManager 打开时机过早，重开（测试模式由 tap 代管 Caps 状态，跳过）
        if ProcessInfo.processInfo.environment["CAPSJ4MAC_TAP_STATE"] != "1",
           controller.capsFlagsSeen > 0, controller.hidEventsSeen == 0 {
            log("看门狗：HID 层未上报 Caps 物理事件，重开 IOHIDManager")
            lastRebuildAt = Date()
            reopenCapsPhysicalMonitor()
        }
    }

    // MARK: 会话/睡眠通知：这些时点后输入管线可能已失效，整体重建

    @objc private func sessionBecameActive() {
        guard hasAllPermissions() else { return }
        log("用户会话已激活，复位大写锁定并重建输入管线")
        clearCapsLockState()
        rebuildEventTap()
        reopenCapsPhysicalMonitor()
    }

    @objc private func systemDidWake() {
        guard hasAllPermissions() else { return }
        log("系统从睡眠唤醒，复位大写锁定并重建输入管线")
        clearCapsLockState()
        rebuildEventTap()
        reopenCapsPhysicalMonitor()
    }

    private func updateUI() {
        let controller = RemapController.shared
        if !hasAllPermissions() {
            statusMenuItem.title = "状态：等待授权（点“权限设置”）…"
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

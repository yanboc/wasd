# Design: add-capslock-remap

## Context

全新项目，无既有代码。目标机器为 Apple Silicon Mac（macOS 26.5），仅有 Command Line Tools（Swift 6.3.3 + macOS 26.5 SDK），未安装 Xcode。动机见 proposal.md。

## Goals / Non-Goals

**Goals:**

- 单个 `swiftc` 命令即可构建出可运行的 `.app`，零第三方依赖
- 事件拦截延迟可忽略（CGEventTap 为系统级同步回调，满足"轻量"要求）
- 权限、签名、暂停/恢复等 macOS 特有的坑在设计中显式处理

**Non-Goals:**

- 不支持用户自定义映射表（映射关系硬编码，后续变更走新 proposal）
- 不做登录自启动的安装器（仅在 README 说明手动添加方式）
- 不处理 Secure Input 场景（密码框等系统会主动断开事件 tap，属可接受行为）

## Decisions

### 1. 用 CGEventTap 而非 IOKit HID 或内核扩展

CGEventTap（`.cgSessionEventTap`）是用户态 API，只需"辅助功能"权限即可全局拦截并改写键盘事件，无需 kext/DriverKit，AppKit 菜单栏应用可天然集成。备选：IOKit HID 更底层但代码量大且无额外收益；Karabiner-Elements 属第三方软件，与"自研 app"目标冲突。

### 2. Caps Lock 状态机：IOHIDManager 跟踪物理按抬 + 吞掉 CGEvent 层信号

**实测结论**：物理 Caps 键在 CGEvent 层是"切换式"信号——每次按下只发一个 `flagsChanged`、交替翻转 `maskAlphaShift`，抬起时不发事件，无法据此跟踪"按住"状态。因此：

- **按住状态**：用 IOHIDManager 监听键盘设备（usage page 0x07 / usage 0x39），HID 层有真实的按下/抬起回调，据此维护 `capsHeld`。需"输入监控"权限（`IOHIDRequestAccess` 触发授权弹窗）
- **CGEvent tap 层**：对 Caps 的 `flagsChanged` 一律返回 `nil` 吞掉，并用 IOKit `IOHIDSetModifierLockState` 强制复位大写锁定（物理按下会在 HID 驱动层翻转锁定状态，吞事件挡不住）。注意只能在事件回调中复位——若在按下路径之外干预会打乱驱动状态机

备选方案（纯 CGEventTap 跟踪 flagsChanged）经实测不可行：抬起事件不存在，状态必然卡死。

### 3. 映射通过"改写事件 keyCode"实现而非重发新事件

在 tap 回调中对映射命中的事件直接修改 keyCode（A=0→←123 等）并返回该事件。相比"吞掉原事件 + `CGEvent.post` 新发事件"，改写能保持事件时序、天然支持自动重复、避免自发事件被 tap 再次拦截的递归问题。修饰键 flags 原样保留即满足"修饰键叠加透传"。

### 4. 单文件 + Makefile + 手工组装 .app，不用 Xcode 工程

机器上无 Xcode；CLT 的 `swiftc` 足以编译 AppKit 应用。`.app` 结构（`Contents/MacOS/` + `Info.plist`）用 Makefile 拼装，`LSUIElement=true` 实现无 Dock 图标。代码量约 300 行，单文件 `Sources/main.swift` 即可，不提前拆分模块。

### 5. ad-hoc 签名起步，自签名证书作为可选增强

`codesign --sign -` 即可本地运行。已知问题：重编译改变二进制哈希后，TCC 可能要求重新授权辅助功能权限。缓解：README 说明如何用钥匙串助手创建自签名证书并以固定身份签名，权限即稳定。不把它列为必做，因为首次使用只需授权一次。

### 6. 事件 tap 失效恢复

回调中监听 `kCGEventTapDisabledByTimeout` / `kCGEventTapDisabledByUserInput`，收到即 `CGEvent.tapEnable` 重新启用——这是 CGEventTap 的标准健壮性模式。

## Risks / Trade-offs

- [吞掉 flagsChanged 挡不住 HID 驱动层的大写锁定（实测确认）] → 每次 Caps 事件回调内用 IOKit `IOHIDSetModifierLockState` 强制复位
- [CGEvent 层无法跟踪 Caps 按住状态（实测确认：抬起无事件）] → IOHIDManager 监听物理按抬，代价是需额外申请"输入监控"权限
- [辅助功能权限被用户撤销后映射静默失效] → 菜单状态项显示权限状态，启动时 `AXIsProcessTrustedWithOptions` 主动提示
- [ad-hoc 签名导致重编译后需重新授权] → README 提供自签名证书方案（见决策 5）
- [Secure Input（密码框）期间事件 tap 被系统断开] → 可接受，恢复普通输入后 tap 自动重连；文档说明
- [菜单栏暂停功能忘了关，用户误以为 app 失效] → 菜单栏图标在暂停时变化（如加斜线/变灰），状态可见

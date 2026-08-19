# Tasks: add-capslock-remap

## 1. 项目骨架

- [x] 1.1 编写 `Info.plist`（bundle id `local.capsj4mac`、`LSUIElement=true`）
- [x] 1.2 编写 `Makefile`（`build` / `run` / `clean`，swiftc -O 编译并组装 `CapsJ4Mac.app`，ad-hoc 签名）
- [x] 1.3 验证 `make build` 产出可启动的空壳 App（菜单栏出现图标）

## 2. 核心映射（对应 keyboard-remapping spec）

- [x] 2.1 创建 CGEventTap（`.cgSessionEventTap`，监听 keyDown/keyUp/flagsChanged），挂入主 RunLoop
- [x] 2.2 实现 Caps Lock 吞掉与 `capsHeld` 状态跟踪（keyCode 57 的 flagsChanged 一律返回 nil）
- [x] 2.3 实现按键映射表：A→←、S→↓、D→→、W→↑、`[`→Home、`]`→End，改写事件 keyCode 返回，修饰键 flags 透传
- [x] 2.4 实现 tap 被系统禁用后的自动恢复（tapEnable）

## 3. 菜单栏与生命周期（对应 app-lifecycle spec）

- [x] 3.1 状态栏图标 + 菜单（状态显示 / 暂停·恢复 / 退出），暂停时图标置灰
- [x] 3.2 暂停时吞掉逻辑整体旁路（所有按键含 Caps 原生放行），恢复后重新生效
- [x] 3.3 启动时检查辅助功能权限，未授权则弹窗提示并在菜单显示"等待授权"
- [x] 3.4 退出时移除 tap 并终止进程

## 4. 验证与收尾

- [x] 4.1 按验证清单在 TextEdit 手动测试全部场景（四方向、Home/End、单按 Caps 无反馈、自动重复、Caps+Shift+A 选中文本、未映射键放行）——自动化注入测试 + 事件日志已验证；物理手感经用户确认
- [x] 4.2 编写 `README.md`（功能、构建、权限授予步骤、自签名证书可选方案、登录项自启动说明、Secure Input 限制）
- [x] 4.3 若单按 Caps 仍触发大写锁定，实现 `IOHIDSetModifierLockState` 兜底复位 —— 已实现且必须：实测确认吞事件挡不住 HID 层锁定
- [x] 4.4 修复 CGEvent 层无法跟踪 Caps 按住状态的问题：改用 IOHIDManager 监听物理按抬（实测确认抬起无 flagsChanged 事件）

# Proposal: add-capslock-remap

## Why

macOS 上没有趁手的轻量工具能把 Caps Lock 改造成纯修饰键用于光标导航。用户希望单手按住 Caps 即可用熟悉的 WASD 键位移动光标、用 `[` `]` 跳行首行尾，同时 Caps Lock 本身不再触发大写锁定，Shift 的中英文切换行为保持由输入法内置功能处理。

## What Changes

- 新建一个 macOS 菜单栏 App（无 Dock 图标），通过 CGEventTap 拦截并改写键盘事件
- Caps Lock 按下期间：A/S/D/W 映射为 ←/↓/→/↑，`[` 映射为 Home，`]` 映射为 End；支持按住自动重复；其他修饰键（如 Shift 选择文本）正常叠加
- 单按 Caps Lock 不产生任何效果（不大写锁定）
- 菜单栏提供：状态显示、启用/暂停映射、退出
- 首次启动引导用户授予"辅助功能"权限

## Capabilities

### New Capabilities

- `keyboard-remapping`: Caps Lock 作为修饰键的按键拦截与重映射（方向键、Home/End、Caps 本身吞掉、修饰键透传、自动重复）
- `app-lifecycle`: 菜单栏 App 的运行形态与生命周期（事件 tap 的创建与被系统禁用后的恢复、启用/暂停切换、辅助功能权限引导、退出）

### Modified Capabilities

（无）

## Impact

- 新增代码：`Sources/main.swift`、`Info.plist`、`Makefile`、`README.md`（全部为新文件，无既有代码改动）
- 系统依赖：macOS 辅助功能权限（Accessibility）；CGEventTap / IOKit / AppKit 框架
- 构建工具链：Swift 6.3.3（Command Line Tools），swiftc 直接编译，无第三方依赖
- 输入法：不拦截 Shift 等任何修饰键

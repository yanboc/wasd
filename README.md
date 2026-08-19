# CapsJ4Mac

轻量级 macOS 键盘映射工具：把 Caps Lock 变成纯导航修饰键。

## 功能

| 按键 | 效果 |
|---|---|
| 单按 Caps Lock | 无任何效果（不再触发大写锁定） |
| Caps + W / A / S / D | ↑ / ← / ↓ / → |
| Caps + `[` / `]` | Home / End |
| Caps + Shift/⌘/⌥ + 映射键 | 修饰键正常叠加（如 Caps+Shift+A = Shift+← 选中文字） |

- 按住映射键支持自动重复
- Shift 等其他修饰键完全不被拦截
- 菜单栏图标运行，可随时暂停/恢复映射；暂停期间 Caps Lock 恢复系统原生大写锁定行为

## 构建与运行

需要 macOS 13+ 和 Command Line Tools（`xcode-select --install`），无需完整 Xcode。

```bash
make build   # 产出 CapsJ4Mac.app
make run     # 构建并启动
make clean
```

## 首次运行：授予辅助功能权限

事件拦截依赖"辅助功能"权限。首次启动时系统会弹出授权提示；也可手动前往：

**系统设置 → 隐私与安全性 → 辅助功能 → 打开 CapsJ4Mac 的开关**

授权后应用自动开始工作（应用每 2 秒轮询一次权限状态，无需重启）。菜单栏图标亮起表示映射生效，置灰表示暂停或等待授权。

## 使用

- 点击菜单栏键盘图标：查看状态、暂停/恢复映射、退出
- 验证：打开文本编辑器，按住 Caps 再按 W/A/S/D 移动光标，Caps+`[`/`]` 跳行首/行尾

## 已知限制与说明

- **Secure Input**：在密码框等安全输入场景，系统会主动断开键盘事件拦截，映射暂时失效，离开该场景后自动恢复
- **重新编译后权限失效**：Makefile 使用 ad-hoc 签名（`codesign --sign -`），二进制哈希每次构建都会变化，macOS 可能要求重新授权辅助功能权限。如需稳定权限，可用"钥匙串访问 → 证书助理 → 创建证书"（代码签名类型）创建自签名证书，然后将 Makefile 中的 `--sign -` 改为 `--sign "你的证书名"`
- **开机自启动**：系统设置 → 通用 → 登录项 → 添加 `CapsJ4Mac.app`

## 测试

```bash
make test
```

会以调试模式（`CAPSJ4MAC_TAP_STATE=1`，由 tap 代管 Caps 状态）重启 App，注入合成按键事件并断言映射结果，测完自动恢复正式实例。测试工具自身也需要辅助功能与输入监控权限。

## 项目结构

```
├── Sources/main.swift   # 全部实现（事件拦截 + 菜单栏 UI，约 230 行）
├── Tests/remap_test.swift  # 端到端注入测试
├── Info.plist           # LSUIElement（无 Dock 图标）
├── Makefile             # build / run / clean
└── openspec/            # OpenSpec 规格与变更记录
```

# CapsJ4Mac

轻量级 macOS 键盘映射工具：把 Caps Lock 变成纯导航修饰键。

作者：yanboc，由 [Kimi Code](https://github.com/MoonshotAI/kimi-code) 辅助开发。

## 下载

从 [Releases](https://github.com/yanboc/capsj4mac/releases) 下载最新的 `CapsJ4Mac-x.y.z.dmg`，打开后将 `CapsJ4Mac.app` 拖入 `Applications`。

本应用使用 ad-hoc 签名（未做 Apple 公证），首次打开会被 Gatekeeper 拦截，任选其一：

- 在 `应用程序` 文件夹中**右键 CapsJ4Mac.app → 打开**，再点"打开"
- 或终端执行：`xattr -dr com.apple.quarantine /Applications/CapsJ4Mac.app`

首次启动会弹出引导窗：辅助功能、输入监控两项权限各有一个"去授权"按钮，点击即直达对应系统设置页，打开开关即可。授权一次永久有效（自签名证书保证），授权后应用自动开始工作。

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
make cert    # 首次构建前生成自签名证书（一次性，稳定 TCC 权限）
make run     # 构建并启动
make icon    # 重新生成应用图标
make clean
```

## 首次运行：授予权限

需要两项权限（系统设置 → 隐私与安全性）：

- **辅助功能**：键盘事件拦截与改写
- **输入监控**：IOHIDManager 监听 Caps 物理按下/抬起

未授权时启动会自动弹出引导窗：每项权限一个"去授权"按钮，点击触发系统授权请求并直达对应设置页，打开 CapsJ4Mac 的开关即可。应用每秒轮询权限状态并实时打勾，两项齐备后引导窗自动关闭、映射自动开始工作，无需重启应用。菜单栏图标亮起表示映射生效，置灰表示暂停或等待授权。

## 使用

- 点击菜单栏键盘图标：查看状态、暂停/恢复映射、退出
- 验证：打开文本编辑器，按住 Caps 再按 W/A/S/D 移动光标，Caps+`[`/`]` 跳行首/行尾

## 已知限制与说明

- **Secure Input**：在密码框等安全输入场景，系统会主动断开键盘事件拦截，映射暂时失效，离开该场景后自动恢复
- **签名与权限稳定性**：默认使用自签名证书 `CapsJ4Mac Signing`（`make cert` 一键生成并导入钥匙串；若首次构建报 `errSecInternalComponent`，按提示执行一次 `security set-key-partition-list -S apple-tool:,apple: -s` 并输入登录密码即可）。固定签名身份让辅助功能授权跨重新构建、跨重启、跨版本升级保持稳定。证书不存在时回退 ad-hoc 签名，此时重编译或重启可能导致权限失效需重新授权
- **开机自启动**：系统设置 → 通用 → 登录项 → 添加 `CapsJ4Mac.app`。登录早期系统会话尚未就绪，可能创建出收不到事件的"死"事件监听；应用内置看门狗会自动检测并重建输入监听（同时在会话激活、睡眠唤醒时也会重建）。若重启后映射仍失效，查看 `~/Library/Logs/CapsJ4Mac.log` 定位原因

## 测试

```bash
make test
```

会以调试模式（`CAPSJ4MAC_TAP_STATE=1`，由 tap 代管 Caps 状态）重启 App，注入合成按键事件并断言映射结果，测完自动恢复正式实例。测试工具自身也需要辅助功能权限（被测实例在调试模式下不依赖"输入监控"）。

## 项目结构

```
├── Sources/main.swift   # 全部实现（事件拦截 + 菜单栏 UI + 自恢复看门狗）
├── Scripts/make_icon.swift  # 图标生成脚本（make icon）
├── Resources/AppIcon.icns   # 应用图标（生成物）
├── Tests/remap_test.swift  # 端到端注入测试
├── Info.plist           # LSUIElement（无 Dock 图标）
├── Makefile             # build / cert / icon / run / clean
└── openspec/            # OpenSpec 规格与变更记录
```

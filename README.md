# WASD

轻量级 macOS 键盘工具：把 Caps Lock 变成纯导航修饰键，短按 Shift 切换中英文。

作者：yanboc，由 [Kimi Code](https://github.com/MoonshotAI/kimi-code) 辅助开发。

## 下载

从 [Releases](https://github.com/yanboc/wasd/releases) 下载最新安装包，打开后将 `WASD.app` 拖入 `Applications`。

1.2.0 之前的安装包文件名是 `CapsJ4Mac-x.y.z.dmg`。换到 WASD 后 bundle id 与签名身份都已更换，需要重新授权一次，并在登录项里改挂 `WASD.app`。

1.2.0 把可执行文件的最低系统误标成 macOS 28，打开时会提示不能与当前系统配合使用。请安装 1.2.1 或更新版本。

本应用使用 ad-hoc 或自签名（未做 Apple 公证），首次打开会被 Gatekeeper 拦截，任选其一：

- 在 `应用程序` 文件夹中**右键 WASD.app → 打开**，再点"打开"
- 或终端执行：`xattr -dr com.apple.quarantine /Applications/WASD.app`

首次启动会弹出引导窗：辅助功能、输入监控两项权限各有一个"去授权"按钮，点击即直达对应系统设置页，打开开关即可。授权一次永久有效（自签名证书保证），授权后应用自动开始工作。

## 功能

| 按键 | 效果 |
|---|---|
| 单按 Caps Lock | 无任何效果（不再触发大写锁定） |
| Caps + W / A / S / D | ↑ / ← / ↓ / → |
| Caps + `[` / `]` | Home / End |
| Caps + Shift/⌘/⌥ + 映射键 | 修饰键正常叠加（如 Caps+Shift+A = Shift+← 选中文字） |
| 单独短按 Shift | 在中文输入源与英文输入源之间切换 |

- 短按指按下到抬起短于 0.3 秒，且期间没有其他键。左 Shift、右 Shift 都可以。这次按键不会再交给输入法，避免连切两次
- 按住 Shift，或 Shift 与其他键一起按，仍然是修饰键（选择文字、快捷键）
- 按住映射键支持自动重复
- 菜单栏图标运行，可随时暂停/恢复。暂停期间 Caps Lock 与 Shift 都恢复系统原生行为

## 构建与运行

需要 macOS 13+ 和 Command Line Tools（`xcode-select --install`），无需完整 Xcode。

```bash
make build   # 产出 WASD.app
make cert    # 首次构建前生成自签名证书（一次性，稳定 TCC 权限）
make run     # 构建并启动
make icon    # 重新生成应用图标
make clean
```

## 首次运行：授予权限

需要两项权限（系统设置 → 隐私与安全性）：

- **辅助功能**：键盘事件拦截与改写
- **输入监控**：IOHIDManager 监听 Caps 物理按下/抬起

未授权时启动会把引导窗放到最前面：每项权限一个"去授权"按钮，点击后打开「系统设置 → 隐私与安全性」里的辅助功能或输入监控。列表里如果还没有 WASD，点该页左下角的 + ，选中引导窗里写的那个 `WASD.app`。应用每秒轮询权限状态并实时打勾，两项齐备后引导窗自动关闭、映射自动开始工作，无需重启应用。菜单栏图标亮起表示映射生效，置灰表示暂停或等待授权。

## 使用

- 点击菜单栏键盘图标：查看状态、暂停/恢复映射、退出
- 验证导航：打开文本编辑器，按住 Caps 再按 W/A/S/D 移动光标，Caps+`[`/`]` 跳行首/行尾
- 验证中英文：单独轻点 Shift，输入源在中文与英文之间切换；再按住 Shift 按方向键，应仍是选择文字而不是切换输入源

## 已知限制与说明

- **Secure Input**：在密码框等安全输入场景，系统会主动断开键盘事件拦截，映射与短按 Shift 暂时失效，离开该场景后自动恢复
- **签名与权限稳定性**：默认使用自签名证书 `WASD Signing`（`make cert` 一键生成并导入钥匙串；若首次构建报 `errSecInternalComponent`，按提示执行一次 `security set-key-partition-list -S apple-tool:,apple: -s` 并输入登录密码即可）。固定签名身份让辅助功能授权跨重新构建、跨重启、跨版本升级保持稳定。证书不存在时回退 ad-hoc 签名，此时重编译或重启可能导致权限失效需重新授权
- **开机自启动**：系统设置 → 通用 → 登录项 → 添加 `WASD.app`。登录早期系统会话尚未就绪，可能创建出收不到事件的"死"事件监听；应用内置看门狗会自动检测并重建输入监听（同时在会话激活、睡眠唤醒时也会重建）。若重启后映射仍失效，查看 `~/Library/Logs/WASD.log` 定位原因
- **输入法自带的 Shift 切换**：短按已被本应用吞掉。输入法里的「使用 Shift 切换中英文」可以留着，但不会再收到这次短按

## 测试

```bash
make test
```

会以调试模式（`WASD_TAP_STATE=1`，由 tap 代管 Caps 状态）重启 App，注入合成按键事件并断言映射结果，测完自动恢复正式实例。测试会短按一次 Shift 并在结束时把输入源切回去。测试工具自身也需要辅助功能权限（被测实例在调试模式下不依赖"输入监控"）。

## 项目结构

```
├── Sources/main.swift          # 全部实现（事件拦截 + 中英文切换 + 菜单栏 UI + 自恢复看门狗）
├── Scripts/make_icon.swift     # 图标生成脚本（make icon）
├── Resources/AppIcon.icns      # 应用图标（生成物）
├── Tests/remap_test.swift      # 端到端注入测试
├── Info.plist                  # LSUIElement（无 Dock 图标）
├── Makefile                    # build / cert / icon / run / clean
└── openspec/                   # OpenSpec 规格与变更记录
```

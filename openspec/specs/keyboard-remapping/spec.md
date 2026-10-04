# keyboard-remapping Specification

## Purpose
把 Caps Lock 改造为纯导航修饰键：按住时 WASD 与括号键映射为方向键和 Home/End，单按 Caps 本身不产生任何效果。

## Requirements

### Requirement: Caps 按住期间的方向键映射

当 Caps Lock 处于按住状态时，系统 SHALL 将 A、S、D、W 按键分别映射为方向键 ←、↓、→、↑，按下与抬起事件都必须映射，目标应用收到的行为与真实方向键一致。

#### Scenario: 按下 Caps+A 产生左方向键

- **WHEN** 用户按住 Caps Lock 再按下 A
- **THEN** 当前应用收到 ← 方向键按下事件，且不收到字符 "a"

#### Scenario: 抬起时序正确

- **WHEN** 用户按住 Caps Lock 并按下 A 后松开 A
- **THEN** 当前应用收到 ← 方向键抬起事件

#### Scenario: 完整四键映射

- **WHEN** 用户按住 Caps Lock 分别按下 W、A、S、D
- **THEN** 当前应用依次收到 ↑、←、↓、→

### Requirement: Caps 按住期间的 Home/End 映射

当 Caps Lock 处于按住状态时，系统 SHALL 将 `[` 映射为 Home，`]` 映射为 End。

#### Scenario: Caps+[ 跳行首

- **WHEN** 用户按住 Caps Lock 按下 `[`
- **THEN** 当前应用收到 Home 键事件，光标移到行首

#### Scenario: Caps+] 跳行尾

- **WHEN** 用户按住 Caps Lock 按下 `]`
- **THEN** 当前应用收到 End 键事件，光标移到行尾

### Requirement: 单按 Caps Lock 无任何效果

系统 SHALL 吞掉 Caps Lock 键自身的事件，使其不触发大写锁定、不改变键盘 LED 状态、不向任何应用传递该按键。

#### Scenario: 单按 Caps 无反馈

- **WHEN** 用户单独按下并松开 Caps Lock（期间不按任何其他键）
- **THEN** 系统不产生大写锁定切换，任何应用都感知不到该按键

### Requirement: 按键自动重复

映射后的按键 MUST 支持与原生按键一致的按住自动重复行为。

#### Scenario: 长按 Caps+D 连续右移

- **WHEN** 用户按住 Caps Lock 并持续按住 D
- **THEN** 当前应用持续收到 → 方向键重复事件，光标连续右移

### Requirement: 修饰键叠加透传

映射发生时，除 Caps Lock 外用户同时按下的修饰键（Shift、Command、Option、Control）MUST 原样保留在映射后的事件上。

#### Scenario: Caps+Shift+A 选中文字

- **WHEN** 用户按住 Caps Lock 和 Shift 再按下 A
- **THEN** 当前应用收到带 Shift 修饰的 ← 方向键，表现为向左选中文字

### Requirement: 未映射按键不受影响

当 Caps Lock 按住时，不在映射表中的按键 MUST 原样放行。Caps Lock 未按住时，除「短按 Shift 切换中英文」外，按键 MUST 不受影响。

#### Scenario: Caps+Q 输出原键

- **WHEN** 用户按住 Caps Lock 按下 Q
- **THEN** 当前应用正常收到 Q 键事件

#### Scenario: 不按 Caps 时普通输入保持原样

- **WHEN** 用户未按住 Caps Lock，按下字母或与 Command、Option、Control 组合
- **THEN** 这些按键行为与未安装本应用时一致

### Requirement: 短按 Shift 切换中英文

映射启用时，单独短按左 Shift 或右 Shift SHALL 在当前中文输入源与英文输入源之间切换。一次短按是指按下到抬起短于 0.3 秒，且期间没有其他按键、鼠标键或其他修饰键。该次 Shift 事件 MUST 被吞掉，不传给当前应用，也不交给输入法再切一次。按住超过 0.3 秒，或与其他键组合时，Shift MUST 仍作为修饰键生效。映射暂停时，Shift MUST 完全恢复系统原生行为。

#### Scenario: 短按 Shift 从中文切到英文

- **WHEN** 映射启用，当前输入源是中文，用户单独短按 Shift
- **THEN** 输入源切到上次使用的英文键盘布局（默认 ABC），当前应用不收到这次 Shift

#### Scenario: 短按 Shift 从英文切回中文

- **WHEN** 映射启用，当前输入源是英文，用户单独短按 Shift
- **THEN** 输入源切回上次使用的中文输入源

#### Scenario: Shift 组合键仍是修饰键

- **WHEN** 用户按下 Shift 后在 0.3 秒内再按 F13，或按住 Shift 超过 0.3 秒
- **THEN** 不切换输入源，目标键带 Shift 修饰


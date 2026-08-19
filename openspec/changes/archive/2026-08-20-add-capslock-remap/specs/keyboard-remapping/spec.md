# Spec: keyboard-remapping

## Purpose

把 Caps Lock 改造为纯导航修饰键：按住时 WASD 与括号键映射为方向键和 Home/End，单按 Caps 本身不产生任何效果。

## ADDED Requirements

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

当 Caps Lock 按住时，不在映射表中的按键 MUST 原样放行；Caps Lock 未按住时，所有按键 MUST 完全不受影响。

#### Scenario: Caps+Q 输出原键

- **WHEN** 用户按住 Caps Lock 按下 Q
- **THEN** 当前应用正常收到 Q 键事件

#### Scenario: 不按 Caps 时键盘行为完全正常

- **WHEN** 用户未按住 Caps Lock 进行任何输入
- **THEN** 所有按键行为与未安装本应用时一致（Shift 等其他修饰键完全透传）

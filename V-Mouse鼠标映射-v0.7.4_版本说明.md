# V-Mouse鼠标映射 v0.7.4

## 当前版本定位

V-Mouse鼠标映射是一款 macOS 鼠标按键二次映射工具。它读取鼠标当前输出的板载键值，在 Mac 软件层执行直通、屏蔽或自定义动作，不写入鼠标固件或板载配置。

## 当前功能

- 板载输入读取与自定义输入分组；
- 按键、快捷键、鼠标、系统、打开目标、命令、文本、宏和配置切换动作；
- 每输入独立拦截及 ⌘/Control 互换；
- VID/PID 设备族与全部条件同时匹配的增强身份识别；
- 多设备、共享配置和无活动配置状态；
- 平滑、方向、轴向和按住型控制等滚轮增强；
- 外接鼠标连接时停用内置触控板；
- 简体中文、English、日本語、한국어、Deutsch 五种界面与帮助；
- 配置迁移、HID 编解码、事件来源和多设备隔离自检。

## 安装要求

- macOS 13 或更高版本；
- 按键二次映射需要辅助功能与输入监控权限；
- 蓝牙电量读取会按需申请蓝牙权限；
- 当前 DMG 为 ad-hoc 签名、未公证安装包。

## 实现与许可

应用使用 Swift、AppKit、IOHIDManager 与 Core Graphics Event Tap。本地配置采用 JSON 保存并原子更新；输入拦截通过带设备来源和校准时间戳的一次性令牌进行关联。

部分代码来自 [DParent10/NagaController](https://github.com/DParent10/NagaController) 和 [Caldis/Mos](https://github.com/Caldis/Mos)。组合版本仅按 CC BY-NC 4.0 提供非商业使用，详情见 `LICENSE` 与 `THIRD_PARTY_NOTICES.md`。

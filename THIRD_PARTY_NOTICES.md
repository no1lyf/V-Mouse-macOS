# 第三方项目与署名

V-Mouse鼠标映射包含以下第三方项目的部分代码或基于其实现进行的修改。发布、分发和再修改时必须保留本文件及根目录 `LICENSE`。

## DParent10/NagaController

- 项目：[DParent10/NagaController](https://github.com/DParent10/NagaController)
- 许可证：MIT
- 使用范围：项目早期的 macOS AppKit 应用结构、Razer Naga 设备监听和按键映射基础实现。
- 本项目的修改：重新设计了设备身份、事件来源关联、配置模型和界面；加入多设备配置、自定义输入分组、五语言本地化、滚轮增强、触控板联动、迁移与自检等功能。

源项目的 MIT 许可文本已保留在根目录 `LICENSE` 中。上述署名不表示原作者认可或担保本项目。

## Caldis/Mos

- 项目：[Caldis/Mos](https://github.com/Caldis/Mos)
- 许可证：[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/)
- 使用范围：macOS 滚轮 Event Tap 处理结构，`Delta`、`PointDelta`、`FixedPtDelta` 三类滚动值的同步反转，平滑和插值思路，模拟触控板滚动阶段，以及 macOS 快捷键分组和按住型滚轮控制交互。
- 本项目的修改：将滚轮处理整合到 V-Mouse 的输入生命周期；排除带滚动阶段或惯性阶段的触控板事件；针对物理滚轮的 `isContinuous`/`scrollCount` 特征调整判定；以主队列串行状态机统一处理停用、断开和动作释放。

Mos 的 CC BY-NC 4.0 条款要求署名、注明修改且不得商业使用。因此，包含这些实现的 V-Mouse 组合发布版本同样仅用于非商业用途。上述署名不表示 Mos 作者认可或担保本项目。

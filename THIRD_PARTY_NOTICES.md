# 版权、许可与资源来源

## SlowFast

Copyright (C) 2026 1anzii

除下列另有声明的第三方资源外，项目源代码、构建脚本、文档与项目自有资源按 **GNU General Public License version 3 only（GPL-3.0-only）** 提供。完整条款见 [LICENSE](LICENSE)。

SlowFast is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3 of the License.

SlowFast is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with SlowFast. If not, see <https://www.gnu.org/licenses/>.

## Michroma 字体

- 文件：`Resources/Fonts/Michroma-Regular.ttf`
- Copyright 2011 The Michroma Project Authors (https://github.com/googlefonts/michroma)
- 独立许可：SIL Open Font License 1.1，[完整条款](Resources/Fonts/OFL.txt)。
- [下载来源及 SHA256](Resources/Fonts/SOURCE.txt)。字体未经修改，仅为当前进程注册。

## 材质、图标与测试视频

`Resources/Textures/BrushedAluminum-v2.png` 为项目通过内置 image_gen 工具生成的原创拉丝金属材质，[最终提示词](Resources/Textures/BrushedAluminum-v2-prompt.txt) 随源码提供。项目在可许可权利范围内按 GPL-3.0-only 提供，不主张 AI 生成材质具有排他权。

图标由 `scripts/cassette-icon.swift` 结合上述材质及 Michroma 字形绘制。SwiftUI / Canvas 原生图形为项目实现，没有复制 STILL 的应用代码或美术资源。

`Resources/connection-test.mp4` 是用 FFmpeg `testsrc2` 生成的合成测试图案，不含第三方影视片段。测试用 Playwright、FFmpeg、Node.js 与 Python，不作为应用运行时分发。

应用使用系统提供的 Apple 框架及 SF Symbols；系统资源不随源码重新分发，也不受项目 GPL 许可约束。

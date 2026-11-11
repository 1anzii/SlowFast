# 开发与测试

## 构建

需要 macOS 13+、Xcode Command Line Tools（`xcode-select --install`）。应用本身无第三方 Swift 依赖。

```sh
bash scripts/build.sh
bash scripts/package.sh
```

默认生成 arm64 + x86_64 通用程序；开发时可用 `ARCHS=arm64 bash scripts/build.sh`。不要把单架构开发构建当成通用 Release 发布。

输出在 `dist/`：应用、DMG、ZIP、SHA256、配套扩展及图标。构建脚本对项目源码路径进行映射，避免把本机用户名和工作路径嵌入发布二进制。`SIGN_IDENTITY` 可指定已有 Developer ID；默认 ad-hoc，不执行 Apple 公证。使用 Developer ID 仍须另行完成公证，签名本身不等于公证。

## 自动测试

测试依赖：Python 3、Node.js 18+、FFmpeg、Playwright（仅开发使用）。`package-lock.json` 固定依赖版本。

```sh
npm ci
# FFmpeg 可使用 Homebrew 安装：brew install ffmpeg
bash scripts/test.sh
CHROME_PATH='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' node Tests/extension.cjs
bash scripts/test-display.sh
bash scripts/test-reels.sh
bash scripts/preview.sh
```

基础网页测试默认使用已安装的 Chrome，也可通过 `CHROME_PATH` 指定另一套测试 Chromium。扩展测试使用单独的 `.build/extension-test-profile`，不会读取日常 Chrome 配置；使用已安装 Chrome 时仅为该测试进程启用官方扩展调试接口。

如不使用已安装 Chrome，可先运行 `npx playwright install chromium --no-shell`，然后不设置 `CHROME_PATH` 运行扩展测试。完整测试浏览器可能需要较大下载。

`scripts/test.sh` 验证速度、Fn 键码映射、浏览器错误分类、配置合并、IINA/mpv 与 VLC 协议及真实 HTML5 视频。`Tests/extension.cjs` 验证 MV3 跨域 iframe、单目标选择、连续指令串行化和快捷键注册。原生渲染测试使用自己的非激活面板，读取实际绘制帧；如果系统开启减少动态效果，动画测试会明确跳过，不应记作动画通过。

实体 Fn 键与真实 macOS 自动化授权须在硬件上验收，自动测试无法代替。IINA / mpv / VLC 协议模拟不等于各播放器所有版本的实机验证。

## 结构

- `Sources/AppModel.swift`：前台目标、串行工作队列、权限和连接状态。
- `Sources/HotKeyListener.swift`：全局 Fn 事件监听，普通按键原样传递。
- `Sources/AppleScriptAdapter.swift`：浏览器与 QuickTime。
- `Sources/LocalAdapters.swift`：本机 IPC / HTTP，超时、响应核对、VLC 重定向拒绝。
- `Sources/ConnectionSupport.swift`：静默连接检测及用户确认后的本地配置。
- `Sources/ConfigEditing.swift`：保留命名配置分组，区分 mpv 全局选项与 `[default]`。
- `Sources/*Design.swift`、`Views.swift`：原生材质、七段数码、点阵与磁带动画。
- `Resources/video.js`：网页视频控制的唯一源文件；构建后复制给应用和扩展。
- `BrowserExtension/`：按指令注入的 MV3 扩展，没有常驻 content script。

只有面板可见时才读取播放状态；隐藏面板停止轮询与绘制。状态回调使用代数标记和进程匹配，防止旧读取结果覆盖切换后的播放器。调速指令排队时也重新核对前台目标。

mpv 分组规则依据：[mpv 官方 Profiles 文档](https://mpv.io/manual/stable/#profiles)。命名分组内的设置不能冒充全局设置；`[default]` 恢复正常全局选项。项目只自动修改明确命名的接口选项，保留其他设置；不尝试完整解析任意脚本、include 链或条件配置。

## 发布输入

`python3 scripts/export-source.py` 以白名单导出干净源码及 UTF-8 ZIP，不导出本机备份、缓存、凭据、日志或实际浏览器配置。材质和字体的来源、许可证随源码提供。导出目录应能独立构建，不依赖工作区其他项目。

请从导出的冻结源码构建正式安装包，再生成包含源码 ZIP 的统一 SHA256 清单。完整步骤见 [PUBLISHING.md](../PUBLISHING.md)。

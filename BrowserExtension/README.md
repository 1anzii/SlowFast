# 可选浏览器扩展

普通 Chrome / Safari 视频通常使用原生应用即可。此扩展用于 Chromium 中需要跨站 iframe 访问的网页；不适用于 Safari。

1. 先运行 `bash scripts/build.sh`。网页控制脚本的唯一源文件是 `Resources/video.js`，构建时会复制到 `dist/BrowserExtension/`。
2. 在 Chromium 浏览器的扩展管理页打开开发者模式，选择「加载已解压的扩展程序」，加载 `dist/BrowserExtension/`。已安装应用可通过「设置 → 高级选项 → 打开配套扩展」定位同一套资源。
3. 在 SlowFast「设置 → 高级选项」开启浏览器扩展模式，回到视频页面使用 Fn 快捷键。

扩展也可独立使用工具栏按钮或 **Control + Shift + , / . / 0**。扩展模式会转发快捷键，原生面板不会假装读到实际倍速；以网页提示为准。

扩展请求网页访问权限是为了按指令查找包含跨站嵌入的视频；没有常驻 content script，不上传页面内容。`chrome://`、商店等受限页面不可访问。本地文件还需要在扩展设置中允许文件访问。

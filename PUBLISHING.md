# 发布 SlowFast

仓库：[1anzii/SlowFast](https://github.com/1anzii/SlowFast)。版本示例：0.4.2。

1. 更新 `Resources/Info.plist`、扩展 manifest、package.json、使用说明与 CHANGELOG。运行开发文档中的相关测试；记录真实结果及未覆盖场景。
2. 执行 `python3 scripts/export-source.py`，得到 `dist/open-source-0.4.2/SlowFast/` 和 `dist/SlowFast-0.4.2-source.zip`。已有同名输出时导出会拒绝覆盖，先另行备份旧产物。
3. 从干净导出目录执行 `bash scripts/build.sh` 与 `bash scripts/package.sh`。验证两种架构、签名、资源、ZIP CRC 与 DMG 校验和。
4. 将干净源码提交到仓库 `main`，新建指向该提交的 `v0.4.2` 标签。只发布白名单源码；不要提交整个开发目录。
5. 在 GitHub 创建 Release，附件包括 DMG、应用 ZIP、源码 ZIP，以及三者的统一 SHA256 清单。先上传草稿并核对附件，再发布。
6. 从公开 Release 下载附件，重新验证 SHA256。确认 README 图片、下载链接和源码目录均可访问。

统一校验清单示例（在附件目录执行）：

```sh
shasum -a 256 SlowFast-0.4.2-mac.dmg SlowFast-0.4.2-mac.zip SlowFast-0.4.2-source.zip > SlowFast-0.4.2-SHA256.txt
shasum -a 256 -c SlowFast-0.4.2-SHA256.txt
```

发布说明应包括 macOS 13+、Apple Silicon / Intel、安装与升级步骤、变更、测试范围，以及 **ad-hoc 临时签名、未经过 Apple 公证**。不得把协议模拟描述为所有播放器版本均实测通过。

每个二进制版本提供对应的可构建源码、脚本和许可。更新现有仓库时保留 `.git` 和原有历史。不得提交证书、密钥、令牌、钥匙串、个人运行记录或备份。不要修改已经发布的同版本附件来隐藏源码变化。

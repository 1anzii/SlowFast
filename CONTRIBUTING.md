# 参与开发

欢迎通过 Issue 报告问题，或提交小范围、可验证的 Pull Request。

请附上 macOS、浏览器/播放器版本、重现步骤和预期行为。日志或截图先去除私人 URL、账号、视频内容、密码和令牌。

调速代码变更请运行 `bash scripts/test.sh`；涉及扩展时运行扩展测试，涉及 UI 动画时运行 `bash scripts/test-display.sh` 与 `bash scripts/test-reels.sh`。具体环境见 [开发文档](docs/DEVELOPMENT.md)。实体 Fn 与真实系统权限无法由单元测试代替，相关改动请说明实机验证范围。

所有贡献按项目 GPL-3.0-only 许可提供，保留第三方资源的原有许可。不要提交 `.build`、`dist`、`Backups`、本机配置或凭据。

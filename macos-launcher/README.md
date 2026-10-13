# BaiduPCS macOS launcher

基于上游 v2.3.0 的原生启动窗口，沿用原有网页及下载引擎。
自有 fork：https://github.com/semantic-craft/BaiduPCS-Rust 。功能分支：`local/macos-launcher`。

## 日常使用

双击 `~/Applications/BaiduPCS.app`。窗口先严格校验整个 App 的签名和资源，再通过 Gatekeeper 评估，只有通过才启动后端并打开默认浏览器。用户自己扫码登录百度网盘；启动器不读取 Cookie、账号文件或后端日志。

重复打开复用窗口。关闭浏览器不停止下载；窗口的“退出”、关闭窗口或 Command-Q 会确认停止传输，向自己启动的后端发送 SIGINT，等待上游保存状态。无法查询活跃下载时也会提示传输风险。未退出成功时保留窗口，不强杀后端。强制结束或崩溃可能遗留后端，重开会提示端口占用，不接管未知进程。

## 唯一目录

- `~/Projects/BaiduPCS-Rust/`：唯一源码仓库，新增代码在本目录和 `backend/examples/desktop-config-check.rs`。
- `~/Applications/BaiduPCS.app/`：整体签名、公证的程序；后端与网页位于 `Contents/Resources/backend`。
- `~/Library/Application Support/BaiduPCS-Rust/`：工作目录，持久保存 `config/`、`wal/` 和上游运行状态；升级应用不覆盖这里。
- `~/Downloads/BaiduPCS-Rust/`：下载文件。

新安装需先准备合法 `config/app.toml`，使用绝对下载路径。现有账号或任务不得被默认配置覆盖。没有自动迁移脚本，避免意外覆盖用户数据。

最小安全设置为 `[server] host="127.0.0.1"`、`port=18888`，以及 `[autobackup] enabled=false`。原版 v2.3.0 包的示例仍含过期 `concurrent_chunks`，需使用当前必需的 `max_global_threads=10`、`max_concurrent_tasks=2`，并保留 `chunk_size_mb`、`max_retries`。独立检查器复用上游完整 AppConfig schema 和路径校验，拒绝错误配置，不让后端悄悄回退默认配置。上游保存后的嵌套 TOML 格式有回归测试。

## 开发与验证

需要 Apple Command Line Tools、Rust、Node/npm。运行 `bash macos-launcher/build.sh` 构建独立配置检查器，运行 Rust 回归测试和 Swift 本地测试，然后构建仅含启动窗口的 `.build/BaiduPCS.app`。不自动运行后端。

`BaiduPCS.app/Contents/MacOS/BaiduPCSLauncher --preview` 只显示窗口，不启动后端、不读取状态或打开网页。普通启动的签名检查有超时；端口被占用时不接管其他进程，健康检查成功后还会核对监听进程归属。

## 整体签名、公证

在已审查且干净的提交上运行 `bash macos-launcher/package.sh`。它从源码和锁文件构建后端、网页和启动层，写入不包含私有路径的源码及工具链 manifest。不会复制旧的受阻发布二进制，不会移除 quarantine。

对 `Contents/Resources/backend/baidu-netdisk-rust`、`Contents/Resources/desktop-config-check`、`Contents/MacOS/BaiduPCSLauncher` 依次用获准的 Developer ID Application 身份执行 `codesign --options runtime --timestamp --sign ID`，然后签名外层 App。不要使用 `--deep` 作为签名方式。

用 `ditto -c -k --keepParent` 制作提交 ZIP，以已有的 notarytool 钥匙串 profile 向 Apple 提交。成功后对 App 执行 `xcrun stapler staple` 和 `validate`，再检查 `codesign --verify --deep --strict` 及 `spctl --assess --type execute`。只有系统认可才运行。签名密钥或公证凭据不进入仓库；钥匙串出现新授权时由用户本人处理。

本分支不配置开机启动、launchd、远程访问或备份任务。未登录的启动验证不代表真实下载已验收。

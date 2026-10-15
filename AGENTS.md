# BaiduPCS-Rust 开发入口

这是自有 fork。产品说明见 [README](README.md)，贡献约定见 [CONTRIBUTING](CONTRIBUTING.md)。本入口对应主分支已有实现。

## 按改动定位

| 改动 | 实现与约束 | 验证入口 |
| --- | --- | --- |
| 网盘协议、任务与配置 | [backend/src](backend/src/)、[贡献指南](CONTRIBUTING.md) | 在 `backend/` 运行 `cargo test` |
| 网页交互 | [frontend/src](frontend/src/)、[脚本定义](frontend/package.json) | 在 `frontend/` 运行 `npm test`、`npm run build` |
| 独立解密工具 | [decrypt-cli](decrypt-cli/) | 先核对该目录的 Cargo 配置与现有测试 |

账号、下载与任务状态属于安装版数据。构建和自动测试不能替代真实传输、下载与安装验收；按具体任务另留证据。
源码改动以当前工作区为基线；贡献指南的上游提交流程不表示应把自有 fork 的改动发往上游。
实现、评审或验收前读相关 [lessons](lessons.md)；出现可复用的纠正或漏验时更新原条目。

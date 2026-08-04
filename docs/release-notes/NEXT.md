# 下一个分支版本草稿

尚未指定下一个候选 Tag。

`v0.6.0-clawgod.1` 的冻结说明位于
[`v0.6.0-clawgod.1.md`](v0.6.0-clawgod.1.md)。发布新的 fork 版本时，请继续
使用中文优先、英文摘要补充的结构，并遵循 [`docs/RELEASING.md`](../RELEASING.md)
中的单 Tag 发布流程。

## 待发布变更

- 安装器在构建前校验 Kiro API Key 或现有登录数据库，避免生成首次请求必然
  401 的安装结果。
- 启动器在自行启动本地网关前再次校验凭据；复用已有网关时还会验证当前
  `KIROCC_API_KEY`，把本地代理密码冲突与上游 Kiro 登录失败明确分开。
- Doctor 增加脱敏的 `kiro-cli whoami` 检查；文档明确 Kiro CLI 只用于创建和
  维护登录凭据，实际对话与 WebSearch 流量由 kirocc 网关直接发送。

## 发布验证清单

- [ ] 指定唯一的 fork 候选 Tag。
- [ ] 更新 `CHANGELOG.md` 和版本化发布说明。
- [ ] 本地检查与 GitHub Linux/Windows CI 全部通过。
- [ ] 只推送单个 fork Tag，不使用 `git push --tags`。
- [ ] 核验全部制品、`checksums.txt` 和 GitHub Release 页面。

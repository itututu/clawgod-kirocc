# 下一个分支预发布版本（计划）

候选 Tag：`v0.6.0-clawgod.1`

这是中文优先的 Release 草稿。维护者明确确认并推送候选 Tag 之前，GitHub
Releases 页面不会出现本项目发行版。

## 主要更新

- `claude-kiro` 默认使用官方 Claude Code runtime，且不修改官方 `claude`
  命令和配置。
- ClawGod v1.7.5 改为显式可选组件，并校验平台安装器 SHA-256。
- 新增 Windows 11 x64 PowerShell 安装、启动、doctor、卸载、测试和 ZIP
  Release 制品。
- Claude Code 内置 WebSearch 改走 Kiro 原生 MCP，支持非流式与 SSE 流式
  响应。
- 提供 macOS/Linux `scripts/doctor.sh` 与 Windows `scripts/doctor.ps1` 只读
  诊断工具。
- GitHub 默认显示完整中文 README，同时保留完整英文说明。

## 安装

GitHub Release 压缩包只包含独立 `kirocc` 网关二进制和公开文档：Windows
使用 ZIP，macOS/Linux 使用 tar.gz。受管理的 `claude-kiro` 必须从源码安装，
因为本项目不重新分发 Claude Code 或本机生成的 ClawGod runtime。

macOS/Linux 默认安装：

```bash
git clone https://github.com/itututu/clawgod-kirocc.git
cd clawgod-kirocc
./scripts/install.sh
./scripts/doctor.sh
```

Windows 默认安装：

```powershell
git clone https://github.com/itututu/clawgod-kirocc.git
Set-Location clawgod-kirocc
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
.\scripts\doctor.ps1
```

默认不安装 ClawGod。只有需要 Patch runtime 时，macOS/Linux 添加
`--with-clawgod`，Windows 添加 `-WithClawGod`。

## 重要边界

- ClawGod 客户端 Patch 不能绕过 Kiro 或 Anthropic 服务端额度、鉴权、计费、
  限流、地区可用性或模型授权。
- 本项目与 Anthropic、Amazon、Kiro、d-kuro、ClawGod 均无隶属关系。
- Release 不包含生成的 runtime、凭据、会话、Provider 数据或完整
  `claude-kiro` 安装目录。
- 仓库继承的上游 `v0.6.0` 及更早 Tag 不会被重新发布为本项目 Release。

## English summary

The first planned fork release is `v0.6.0-clawgod.1`. It adds a managed
Windows 11 x64 profile, Kiro-native WebSearch, an official Claude Code runtime
by default, and checksum-verified ClawGod as an explicit opt-in. Release
archives contain only the standalone gateway and public documentation; clone
the source for the managed `claude-kiro` installation.

## 发布验证清单

- [ ] 本地 Go race、vet、Shell、PowerShell、JSON 和 SVG 检查通过。
- [ ] 候选提交对应的 GitHub Linux/Windows CI 全部通过。
- [ ] macOS arm64 全新默认安装的隔离边界复核通过。
- [ ] Linux 压缩包解压以及 `kirocc --help` 通过。
- [ ] Windows ZIP 解压以及 `kirocc.exe --help` 通过。
- [ ] 维护者确认候选版本号和发布操作。
- [ ] 只推送单个 fork Tag，不使用 `git push --tags`。

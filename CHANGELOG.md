# Changelog

All notable changes to this fork are documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses fork-specific
pre-release tags based on the upstream kirocc version.

## [Unreleased]

## [v0.6.0-clawgod.2] - 2026-08-03

### Changed

- Documentation now makes the traffic boundary explicit: Kiro CLI is only a
  login-database bootstrap/maintenance tool, while the kirocc gateway sends
  chat and WebSearch requests directly to Kiro.

### Fixed

- The macOS/Linux and Windows installers now reject a missing Kiro credential
  source before building, while preserving Kiro API-key mode with no Kiro CLI
  dependency.
- Generated launchers now fail with actionable Kiro login instructions when a
  local gateway would start without a database or API key.
- Launchers authenticate an already-running gateway's `/v1/models` endpoint so
  a stale process with a different `KIROCC_API_KEY` is reported before Claude
  Code encounters a misleading local 401.
- Doctor scripts now check `kiro-cli whoami` without displaying account output
  and distinguish an optional missing CLI command from a missing login database.
- The Windows installer now reports the exact active `go.exe` path and version,
  and rejects Go versions older than the `go.mod` requirement before attempting
  a `GOEXPERIMENT=jsonv2` build.

## [v0.6.0-clawgod.1] - 2026-08-03

### Added

- An isolated `claude-kiro` launcher and configuration profile that use the
  official Claude Code runtime by default and leave `claude` untouched.
- Native Windows 11 x64 PowerShell install, launcher, doctor, uninstall, CI,
  and release support.
- A pinned, checksum-verified ClawGod v1.7.5 installation flow with generated
  runtime files kept outside Git.
- Kiro-native WebSearch translation for Anthropic server-tool requests,
  including non-streaming and SSE responses, credential refresh, and retry
  handling.
- A read-only `scripts/doctor.sh` command for installation, isolation,
  credential-source, port, and gateway-health diagnostics.
- English and Chinese setup, architecture, capability, security, and
  troubleshooting documentation.

### Changed

- GitHub now renders the complete Chinese documentation by default from
  `README.md`; the complete English documentation is available in
  `README_EN.md`, and the first fork release draft is Chinese-first.
- ClawGod is now an explicit optional component selected with
  `--with-clawgod` / `-WithClawGod`; it is no longer downloaded by default.
- The managed gateway uses port `3457` by default to avoid the upstream
  standalone default on `3456`.
- The installer accepts either `shasum` or `sha256sum` for macOS/Linux
  checksum verification.
- The release workflow accepts fork tags matching `v*-clawgod.*`; inherited
  upstream tags must not be republished.
- GoReleaser publishes Windows binaries as ZIP archives in addition to the
  macOS/Linux tarballs.

### Security

- Generated Claude Code/ClawGod files, credentials, provider files, sessions,
  and logs are excluded from the repository.
- In-place `claude-kiro update` is blocked to preserve the isolated path and
  verified installer boundary.

[Unreleased]: https://github.com/itututu/clawgod-kirocc/compare/v0.6.0-clawgod.2...HEAD
[v0.6.0-clawgod.2]: https://github.com/itututu/clawgod-kirocc/compare/v0.6.0-clawgod.1...v0.6.0-clawgod.2
[v0.6.0-clawgod.1]: https://github.com/itututu/clawgod-kirocc/releases/tag/v0.6.0-clawgod.1

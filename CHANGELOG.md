# Changelog

All notable changes to this fork are documented here. The project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and uses fork-specific
pre-release tags based on the upstream kirocc version.

## [Unreleased]

### Added

- An isolated `claude-kiro` launcher and configuration profile that leave the
  official `claude` command untouched.
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

- The managed gateway uses port `3457` by default to avoid the upstream
  standalone default on `3456`.
- The installer accepts either `shasum` or `sha256sum` for macOS/Linux
  checksum verification.
- The release workflow accepts fork tags matching `v*-clawgod.*`; inherited
  upstream tags must not be republished.

### Security

- Generated Claude Code/ClawGod files, credentials, provider files, sessions,
  and logs are excluded from the repository.
- In-place `claude-kiro update` is blocked to preserve the isolated path and
  verified installer boundary.

[Unreleased]: https://github.com/itututu/clawgod-kirocc/commits/main

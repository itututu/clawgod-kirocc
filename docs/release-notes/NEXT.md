# Next fork release (planned)

Candidate tag: `v0.6.0-clawgod.1`

This document is a release draft. No tag or GitHub Release exists until the
maintainer explicitly approves and pushes the candidate tag.

## Highlights

- Isolated `claude-kiro` launcher using official Claude Code by default, with
  the official `claude` command and profile left untouched.
- ClawGod v1.7.5 is a checksum-verified opt-in instead of a mandatory install.
- Native Windows 11 x64 PowerShell installer, launcher, doctor, uninstall,
  tests, and ZIP release artifacts.
- Kiro-native WebSearch support for Claude Code's built-in Anthropic server
  tool, including streaming and non-streaming responses.
- Read-only installation diagnostics through `scripts/doctor.sh` and
  `scripts/doctor.ps1`.
- Complete English and Chinese setup, capability, architecture, security, and
  troubleshooting documentation.

## Installation

The GitHub release archives contain the standalone `kirocc` gateway binary
(Windows uses ZIP; macOS/Linux use tar.gz).
The managed profile must be installed from a source checkout. The repository
does not redistribute Claude Code or generated ClawGod runtime files:

```bash
git clone https://github.com/itututu/clawgod-kirocc.git
cd clawgod-kirocc
./scripts/install.sh
./scripts/doctor.sh
```

Add `--with-clawgod` only when the patched runtime is wanted. On Windows use
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File
.\scripts\install.ps1`, optionally with `-WithClawGod`.

## Important boundaries

- ClawGod client-side patches do not bypass Kiro or Anthropic server-side
  quota, authentication, billing, rate limits, regional availability, or model
  authorization.
- The project is not affiliated with Anthropic, Amazon, Kiro, d-kuro, or
  ClawGod.
- Generated runtime files, credentials, sessions, and provider data are not
  release artifacts.

## Validation checklist

- [ ] Local Go race tests, vet, shell syntax, JSON, and SVG validation pass.
- [ ] GitHub CI passes on the exact release commit.
- [ ] Clean-install isolation is rechecked on macOS arm64.
- [ ] Linux archive extraction and `kirocc --help` are checked.
- [ ] Windows ZIP extraction and `kirocc.exe --help` are checked.
- [ ] Release notes are updated from this draft before the tag is pushed.

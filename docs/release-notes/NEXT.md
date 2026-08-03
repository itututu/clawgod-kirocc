# Next fork release (planned)

Candidate tag: `v0.6.0-clawgod.1`

This document is a release draft. No tag or GitHub Release exists until the
maintainer explicitly approves and pushes the candidate tag.

## Highlights

- Isolated `claude-kiro` launcher with the official `claude` command and profile
  left untouched.
- Checksum-verified ClawGod v1.7.5 runtime generation outside the repository.
- Kiro-native WebSearch support for Claude Code's built-in Anthropic server
  tool, including streaming and non-streaming responses.
- Read-only installation diagnostics through `scripts/doctor.sh`.
- Complete English and Chinese setup, capability, architecture, security, and
  troubleshooting documentation.

## Installation

The GitHub release archives contain the standalone `kirocc` gateway binary.
The complete ClawGod profile must be installed from a source checkout because
the repository intentionally does not redistribute Claude Code or generated
ClawGod runtime files:

```bash
git clone https://github.com/itututu/clawgod-kirocc.git
cd clawgod-kirocc
./scripts/install.sh
./scripts/doctor.sh
```

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
- [ ] Release notes are updated from this draft before the tag is pushed.

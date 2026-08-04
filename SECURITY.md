# Security and privacy

## Local data boundary

The gateway reads Kiro CLI credentials from the local Kiro CLI database or from
an explicitly supplied `KIRO_API_KEY`. Credentials are used only for calls to
Kiro endpoints and must never be committed to this repository.

The following generated paths are local-only and are not project artifacts:

- `~/.clawgod-kirocc/`
- `%LOCALAPPDATA%\ClawGodKiroCC\clawgod-kirocc\`
- `%USERPROFILE%\.clawgod-kirocc\`
- `~/.claude/` and any configured `CLAUDE_CONFIG_DIR`
- Kiro CLI `data.sqlite3`
- generated `cli.cjs`, provider files, histories, logs, and access tokens

## Reporting

Please open a GitHub security advisory for credential disclosure, authentication
bypass, unsafe installer behavior, or unintended writes to the official Claude
Code installation. Do not include live tokens, provider files, or session logs.

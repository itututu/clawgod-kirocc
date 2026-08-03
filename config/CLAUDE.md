# ClawGod KiroCC runtime profile

- Prefer Claude Code's built-in `WebSearch` tool for internet research. The local gateway maps it to Kiro's native MCP web search endpoint.
- When native WebSearch reports an upstream failure, use an explicitly configured search MCP only as a fallback.
- Include relevant source URLs in answers based on internet research.
- Preserve the user's official Claude Code installation and configuration. Do not run `claude update` or `clawgod update` from this isolated profile.
- Treat Kiro credentials, provider files, Claude session history, and generated patched runtime files as local secrets. Never add them to a repository.
- Verify code changes with the repository's tests and state any live-validation boundary honestly.

# Contributing

Thanks for improving ClawGod KiroCC. This repository is a downstream fork of
kirocc, so changes should keep the upstream gateway boundary and the isolated
ClawGod integration easy to audit.

## Before opening an issue

- Run `./scripts/doctor.sh` and remove paths or values you do not want public.
- Search existing issues and confirm whether the problem belongs to this fork,
  upstream kirocc, ClawGod, Kiro CLI, or Claude Code.
- Never post credentials, tokens, provider files, generated `cli.cjs`, private
  prompts, local databases, source code from proprietary runtimes, or session
  logs.
- Report security-sensitive problems through the process in
  [`SECURITY.md`](SECURITY.md), not a public issue.

## Development setup

Prerequisites are Go 1.26+, Node.js 18+, Bash, and the tools listed in the
README. A Kiro credential is not required for unit tests.

```bash
git clone https://github.com/itututu/clawgod-kirocc.git
cd clawgod-kirocc
make test
GOEXPERIMENT=jsonv2 go vet ./...
bash -n scripts/install.sh scripts/uninstall.sh scripts/doctor.sh
./scripts/doctor.sh --help >/dev/null
python3 -m json.tool config/settings.json >/dev/null
```

`make test` runs the Go test suite with the race detector. Tests that contact a
live Kiro account must be opt-in, redact credentials, and state what remote
behavior they actually proved.

## Pull requests

- Keep changes focused and explain whether they modify upstream-derived code,
  fork integration code, generated-runtime behavior, or documentation only.
- Add or update tests for protocol, streaming, retry, launcher, or installer
  behavior.
- Keep `README.md` and `README_ZH.md` aligned when changing user-facing setup,
  flags, environment variables, capabilities, or limitations.
- Do not vendor downloaded installers, generated ClawGod runtime files,
  extracted Claude Code source, credentials, histories, or logs.
- Preserve the official `claude` command and configuration boundary.
- Run the validation commands above and include the result in the PR.

By submitting a contribution, you agree that it is licensed under the
repository's Apache-2.0 license and that you have the right to contribute it.

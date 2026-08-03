## Summary

Describe the problem and the smallest implemented change.

## Scope

- [ ] Upstream-derived gateway code
- [ ] Kiro-native WebSearch
- [ ] ClawGod isolation or launcher
- [ ] Installer or diagnostics
- [ ] Documentation only

## Validation

- [ ] `make test`
- [ ] `GOEXPERIMENT=jsonv2 go vet ./...`
- [ ] `bash -n scripts/install.sh scripts/uninstall.sh scripts/doctor.sh`
- [ ] `./scripts/doctor.sh --help`
- [ ] `python3 -m json.tool config/settings.json`
- [ ] Live validation, if claimed, is described below with credentials redacted

## Safety and documentation

- [ ] The official `claude` command and profile remain untouched
- [ ] No credentials, generated runtime files, proprietary source/prompts, or session logs are included
- [ ] Tests cover changed behavior or the reason they do not is explained
- [ ] `README.md` and `README_ZH.md` remain aligned for user-facing changes

## Evidence

Paste concise, redacted test output or explain why it is not applicable.

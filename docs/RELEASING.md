# Fork release process

This repository inherits kirocc's upstream tags through `v0.6.0`. Fork
releases therefore use a distinct pre-release suffix and must never republish
the inherited upstream tags to `origin`.

The current candidate is `v0.6.0-clawgod.2`. Creating a tag or GitHub Release
is a maintainer decision and is intentionally separate from preparing code and
release notes.

## Artifact boundary

GoReleaser publishes standalone `kirocc` gateway binaries for macOS, Linux,
and Windows on amd64 and arm64. Windows artifacts use ZIP; macOS/Linux use
tar.gz. Those archives do not contain Claude Code, ClawGod runtime
files, credentials, or the complete-profile installer output.

Users who want `claude-kiro` must clone the source and run
`./scripts/install.sh` (or `scripts\install.ps1` on Windows). The default uses
official Claude Code; when ClawGod is explicitly selected, the installer
downloads the pinned platform installer, verifies its checksum, and generates
the isolated runtime locally.

## Tag scheme

Use:

```text
v<upstream-version>-clawgod.<fork-release-number>
```

Examples:

- `v0.6.0-clawgod.1`
- `v0.6.0-clawgod.2`

The release workflow only accepts tags matching `v*-clawgod.*`. When rebasing
onto a later kirocc release, update the upstream-version component and reset the
fork release number only if that lineage is clear in the release notes.

## Prepare a release

1. Update and verify `main`:

   ```bash
   git switch main
   git pull --ff-only origin main
   git status --short
   ```

2. Confirm that the candidate tag does not already exist locally or remotely:

   ```bash
   git show-ref --tags --verify refs/tags/v0.6.0-clawgod.1 || true
   git ls-remote --exit-code --tags origin refs/tags/v0.6.0-clawgod.1 || true
   ```

3. Update `CHANGELOG.md` and copy `docs/release-notes/NEXT.md` to a versioned
   release-note file.

4. Run the complete local validation:

   ```bash
   make test
   GOEXPERIMENT=jsonv2 go vet ./...
   bash -n scripts/install.sh scripts/uninstall.sh scripts/doctor.sh
   ./scripts/doctor.sh --help >/dev/null
   python3 -m json.tool config/settings.json >/dev/null
   xmllint --noout docs/assets/comparison.svg
   GOOS=windows GOARCH=amd64 CGO_ENABLED=0 GOEXPERIMENT=jsonv2 go build -o /tmp/kirocc.exe ./cmd/kirocc
   ```

5. Push the release-preparation commit and wait for CI to pass on that exact
   commit. Do not push `--tags`.

## Publish after explicit approval

Replace the candidate below if a different version was approved:

```bash
git switch main
git pull --ff-only origin main
git tag -a v0.6.0-clawgod.1 -m "ClaudeCode Kiro v0.6.0-clawgod.1"
git push origin refs/tags/v0.6.0-clawgod.1
```

The tag triggers `.github/workflows/release.yml`. After it succeeds, replace
the automatically generated notes with the reviewed version:

```bash
gh release edit v0.6.0-clawgod.1 \
  --notes-file docs/release-notes/v0.6.0-clawgod.1.md
```

Do not use `git push --tags`: it can publish inherited upstream tags and create
ambiguous releases.

## Release checklist

- [ ] Candidate tag is unique locally and on `origin`.
- [ ] `CHANGELOG.md` and versioned release notes match the code.
- [ ] Local validation passes.
- [ ] GitHub CI passes on the exact commit.
- [ ] The maintainer explicitly approved the version and publication.
- [ ] Only the single fork tag was pushed.
- [ ] GoReleaser completed for all six OS/architecture targets.
- [ ] Checksums and extracted `kirocc --help` were verified.
- [ ] GitHub Release notes were replaced with the reviewed markdown.

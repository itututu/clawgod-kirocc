#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install_root="${CLAWGOD_KIROCC_INSTALL_ROOT:-$HOME/.local/share/clawgod-kirocc}"
state_root="${CLAWGOD_KIROCC_STATE_ROOT:-$HOME/.clawgod-kirocc}"
user_bin_dir="${CLAWGOD_KIROCC_BIN_DIR:-$HOME/.local/bin}"
gateway_port="${KIROCC_PORT:-3457}"
clawgod_release="${CLAWGOD_RELEASE:-v1.7.5}"
clawgod_installer_sha256="${CLAWGOD_INSTALLER_SHA256:-4a943439ae8cb858e69279d19f0d3a979968fc0a9e4c42e1d1018ae76657ce82}"
refresh_clawgod=false
gateway_only=false

usage() {
  cat <<'USAGE'
Usage: ./scripts/install.sh [--refresh-clawgod] [--gateway-only]

  --refresh-clawgod  Rebuild the isolated ClawGod runtime even when present.
  --gateway-only     Install the patched kirocc and launcher around CLAWGOD_BIN.

Environment overrides:
  CLAWGOD_BIN                    Existing explicit ClawGod launcher.
  CLAWGOD_RELEASE                ClawGod release tag (default: v1.7.5).
  CLAWGOD_INSTALLER_SHA256       Required checksum when changing the release.
  CLAWGOD_KIROCC_INSTALL_ROOT    Runtime installation root.
  CLAWGOD_KIROCC_STATE_ROOT      Isolated ClawGod state/config root.
  CLAWGOD_KIROCC_BIN_DIR         Directory for the claude-kiro launcher.
  KIROCC_PORT                    Gateway port (default: 3457).
USAGE
}

while (($# > 0)); do
  case "$1" in
    --refresh-clawgod) refresh_clawgod=true ;;
    --gateway-only) gateway_only=true ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$gateway_port" in
  ''|*[!0-9]*) printf 'KIROCC_PORT must be numeric\n' >&2; exit 2 ;;
esac
if ((gateway_port < 1 || gateway_port > 65535)); then
  printf 'KIROCC_PORT must be between 1 and 65535\n' >&2
  exit 2
fi

for required_command in go curl node bun rg; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'missing prerequisite: %s\n' "$required_command" >&2
    exit 127
  fi
done

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    printf 'missing prerequisite: shasum or sha256sum\n' >&2
    return 127
  fi
}

mkdir -p "$install_root/bin" "$install_root/clawgod/bin" "$state_root/claude-config" "$user_bin_dir"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/clawgod-kirocc.XXXXXX")"
cleanup_install() {
  rm -rf "$temporary_root"
}
trap cleanup_install EXIT INT TERM HUP

printf 'Building patched kirocc...\n'
GOEXPERIMENT=jsonv2 go build -trimpath -o "$temporary_root/kirocc" "$project_root/cmd/kirocc"
install -m 0755 "$temporary_root/kirocc" "$install_root/bin/kirocc-native-websearch"

runtime_clawgod_bin="${CLAWGOD_BIN:-$install_root/clawgod/bin/clawgod}"
if [[ "$gateway_only" == false && ("$refresh_clawgod" == true || ! -x "$runtime_clawgod_bin") ]]; then
  if [[ "$clawgod_release" != "v1.7.5" && -z "${CLAWGOD_INSTALLER_SHA256:-}" ]]; then
    printf 'CLAWGOD_INSTALLER_SHA256 is required for ClawGod releases other than v1.7.5\n' >&2
    exit 2
  fi

  clawgod_installer="$temporary_root/clawgod-install.sh"
  clawgod_url="https://github.com/0Chencc/clawgod/releases/download/${clawgod_release}/install.sh"
  printf 'Downloading ClawGod %s installer...\n' "$clawgod_release"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "$clawgod_installer" "$clawgod_url"

  actual_sha256="$(sha256_file "$clawgod_installer")"
  if [[ "$actual_sha256" != "$clawgod_installer_sha256" ]]; then
    printf 'ClawGod installer checksum mismatch\nexpected: %s\nactual:   %s\n' \
      "$clawgod_installer_sha256" "$actual_sha256" >&2
    exit 1
  fi

  # Add three opt-in path overrides to the downloaded GPL installer. The
  # modified installer runs only from the temporary directory and is never
  # redistributed. Its output remains under the isolated roots above.
  node - "$clawgod_installer" <<'NODE'
const fs = require('fs');
const path = process.argv[2];
let source = fs.readFileSync(path, 'utf8');
const replacements = [
  ['CLAWGOD_DIR="$HOME/.clawgod"', 'CLAWGOD_DIR="${CLAWGOD_DIR_OVERRIDE:-$HOME/.clawgod}"'],
  ['BIN_DIR="$HOME/.local/bin"', 'BIN_DIR="${CLAWGOD_BIN_DIR_OVERRIDE:-$HOME/.local/bin}"'],
  ['CLAUDE_BIN=$(command -v claude 2>/dev/null || true)', 'CLAUDE_BIN="${CLAWGOD_CLAUDE_BIN_OVERRIDE:-$(command -v claude 2>/dev/null || true)}"'],
  ['CLAUDE_SETTINGS="$HOME/.claude/settings.json"', 'CLAUDE_SETTINGS="${CLAWGOD_CLAUDE_SETTINGS_OVERRIDE:-$HOME/.claude/settings.json}"'],
  ['CLAUDE_SETTINGS_DIR="$HOME/.claude"', 'CLAUDE_SETTINGS_DIR="${CLAWGOD_CLAUDE_SETTINGS_DIR_OVERRIDE:-$HOME/.claude}"'],
  ["const clawgodDir = join(homedir(), '.clawgod');", "const clawgodDir = process.env.CLAWGOD_RUNTIME_STATE_ROOT || join(homedir(), '.clawgod');"],
  ["const nativeClaudeJson = join(homedir(), '.claude.json');", "const nativeClaudeJson = join(process.env.CLAUDE_CONFIG_DIR || homedir(), '.claude.json');"],
];
for (const [before, after] of replacements) {
  if (!source.includes(before)) throw new Error(`unsupported ClawGod installer: missing ${before}`);
  source = source.split(before).join(after);
}
fs.writeFileSync(path, source);
NODE

  official_claude_command="$(command -v claude 2>/dev/null || true)"
  if [[ -z "$official_claude_command" ]]; then
    printf 'official Claude Code command not found; install it before ClawGod\n' >&2
    exit 127
  fi
  official_claude_candidate="$official_claude_command"
  if [[ -e "${official_claude_command}.orig" ]]; then
    official_claude_candidate="${official_claude_command}.orig"
  fi
  official_claude_real="$(node -e 'console.log(require("fs").realpathSync(process.argv[1]))' "$official_claude_candidate")"

  CLAWGOD_DIR_OVERRIDE="$state_root" \
  CLAWGOD_BIN_DIR_OVERRIDE="$install_root/clawgod/bin" \
  CLAWGOD_CLAUDE_BIN_OVERRIDE="$install_root/clawgod/bin/claude" \
  CLAWGOD_CLAUDE_SETTINGS_OVERRIDE="$state_root/claude-config/settings.json" \
  CLAWGOD_CLAUDE_SETTINGS_DIR_OVERRIDE="$state_root/claude-config" \
  CLAWGOD_RUNTIME_STATE_ROOT="$state_root" \
  CLAUDE_CONFIG_DIR="$state_root/claude-config" \
    bash "$clawgod_installer" --lean-off

  # ClawGod uses claude.orig for shell integration and child dispatch. Create
  # that reference inside the isolated prefix without altering the official
  # launcher or its adjacent files.
  ln -sfn "$official_claude_real" "$install_root/clawgod/bin/claude.orig"

  # ClawGod's generated JS wrapper normally derives ~/.clawgod from HOME.
  # Point this local copy at the isolated state root and respect our separate
  # Claude configuration directory.
  node - "$state_root/cli.cjs" "$state_root" <<'NODE'
const fs = require('fs');
const path = process.argv[2];
const stateRoot = process.argv[3];
let source = fs.readFileSync(path, 'utf8');
const dirNeedles = [
  "const clawgodDir = process.env.CLAWGOD_RUNTIME_STATE_ROOT || join(homedir(), '.clawgod');",
  "const clawgodDir = join(homedir(), '.clawgod');",
];
const dirNeedle = dirNeedles.find(needle => source.includes(needle));
if (!dirNeedle) throw new Error('unsupported ClawGod wrapper: state root marker not found');
source = source.replace(dirNeedle, `const clawgodDir = ${JSON.stringify(stateRoot)};`);
source = source.replace(
  "const nativeClaudeJson = join(homedir(), '.claude.json');",
  "const nativeClaudeJson = join(process.env.CLAUDE_CONFIG_DIR || homedir(), '.claude.json');",
);
fs.writeFileSync(path, source);
NODE

  # Disable in-place updates: rerun this installer so the same isolation and
  # checksum checks are applied to every refresh.
  for generated_launcher in "$install_root/clawgod/bin/clawgod" "$install_root/clawgod/bin/claude"; do
    node - "$generated_launcher" <<'NODE'
const fs = require('fs');
const path = process.argv[2];
let source = fs.readFileSync(path, 'utf8');
const marker = '# Route \'import\' subcommand to clawgod-import binary';
const guard = `if [ "\${1:-}" = "update" ]; then
  echo "clawgod-kirocc: run the project installer with --refresh-clawgod to update safely" >&2
  exit 2
fi
`;
if (!source.includes(marker)) throw new Error('unsupported ClawGod launcher: marker not found');
source = source.replace(marker, guard + marker);
fs.writeFileSync(path, source);
NODE
    chmod 0755 "$generated_launcher"
  done
  runtime_clawgod_bin="$install_root/clawgod/bin/clawgod"
fi

if [[ ! -x "$runtime_clawgod_bin" ]]; then
  printf 'ClawGod launcher not found: %s\nSet CLAWGOD_BIN or omit --gateway-only.\n' "$runtime_clawgod_bin" >&2
  exit 127
fi

if [[ ! -f "$state_root/claude-config/CLAUDE.md" ]]; then
  install -m 0644 "$project_root/config/CLAUDE.md" "$state_root/claude-config/CLAUDE.md"
fi
if [[ ! -f "$state_root/claude-config/settings.json" ]]; then
  install -m 0644 "$project_root/config/settings.json" "$state_root/claude-config/settings.json"
fi

launcher_path="$user_bin_dir/claude-kiro"
cat > "$launcher_path" <<LAUNCHER
#!/usr/bin/env bash
set -euo pipefail

kirocc_bin="\${KIROCC_BIN:-$install_root/bin/kirocc-native-websearch}"
clawgod_bin="\${CLAWGOD_BIN:-$runtime_clawgod_bin}"
config_dir="\${CLAWGOD_KIROCC_CONFIG_DIR:-$state_root/claude-config}"
gateway_port="\${KIROCC_PORT:-$gateway_port}"
gateway_url="\${KIROCC_URL:-http://127.0.0.1:\${gateway_port}}"
proxy_token="\${KIROCC_API_KEY:-dummy}"
log_file="\${TMPDIR:-/tmp}/clawgod-kirocc-gateway-\${UID}-\${gateway_port}.log"
started_pid=""

cleanup() {
  if [[ -n "\$started_pid" ]] && kill -0 "\$started_pid" 2>/dev/null; then
    kill "\$started_pid" 2>/dev/null || true
    wait "\$started_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM HUP

if [[ "\${1:-}" == "update" ]]; then
  echo "claude-kiro: updates are disabled in the isolated profile; rerun scripts/install.sh" >&2
  exit 2
fi

if ! curl -fsS --max-time 1 "\$gateway_url/health" >/dev/null 2>&1; then
  "\$kirocc_bin" -port "\$gateway_port" >"\$log_file" 2>&1 &
  started_pid=\$!
  ready=false
  for _attempt in {1..50}; do
    if curl -fsS --max-time 1 "\$gateway_url/health" >/dev/null 2>&1; then
      ready=true
      break
    fi
    if ! kill -0 "\$started_pid" 2>/dev/null; then break; fi
    sleep 0.1
  done
  if [[ "\$ready" != true ]]; then
    echo "claude-kiro: gateway failed to start; log follows" >&2
    tail -n 40 "\$log_file" >&2 2>/dev/null || true
    exit 1
  fi
fi

/usr/bin/env \
  -u ANTHROPIC_API_KEY \
  -u CLAUDE_CODE_USE_BEDROCK \
  -u CLAUDE_CODE_USE_VERTEX \
  -u CLAUDE_CODE_USE_FOUNDRY \
  CLAUDE_CONFIG_DIR="\$config_dir" \
  ANTHROPIC_BASE_URL="\$gateway_url" \
  ANTHROPIC_AUTH_TOKEN="\$proxy_token" \
  "\$clawgod_bin" "\$@"
LAUNCHER
chmod 0755 "$launcher_path"

printf '\nInstalled successfully:\n'
printf '  launcher: %s\n' "$launcher_path"
printf '  gateway:  %s\n' "$install_root/bin/kirocc-native-websearch"
printf '  ClawGod:  %s\n' "$runtime_clawgod_bin"
printf '  config:    %s\n' "$state_root/claude-config"
printf '  command:   claude-kiro\n\n'
printf 'The official claude command was not modified by this installer.\n'

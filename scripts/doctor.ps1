#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Strict,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    @"
Usage: .\scripts\doctor.ps1 [-Strict]

Read-only checks for the Windows ClaudeCode Kiro installation. It never prints
tokens, modifies configuration, starts Claude Code, or starts/stops the gateway.
"@ | Write-Host
    exit 0
}

function Get-EnvOrDefault([string]$Name, [string]$DefaultValue) {
    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($value) { return $value }
    return $DefaultValue
}

$UserBinDir = Get-EnvOrDefault "CLAWGOD_KIROCC_BIN_DIR" (Join-Path $env:USERPROFILE ".local\bin")
$launcherConfigPath = if ($env:CLAWGOD_KIROCC_LAUNCHER_CONFIG) {
    $env:CLAWGOD_KIROCC_LAUNCHER_CONFIG
} else {
    Join-Path $UserBinDir "clawgod-kirocc-launcher.json"
}
$launcherConfig = $null
if (Test-Path -LiteralPath $launcherConfigPath -PathType Leaf) {
    try {
        $launcherConfig = Get-Content -LiteralPath $launcherConfigPath -Raw | ConvertFrom-Json
    } catch {
        $launcherConfig = $null
    }
}

$defaultInstallRoot = Join-Path $env:LOCALAPPDATA "ClawGodKiroCC\clawgod-kirocc"
$InstallRoot = if ($env:CLAWGOD_KIROCC_INSTALL_ROOT) {
    $env:CLAWGOD_KIROCC_INSTALL_ROOT
} elseif ($launcherConfig) {
    [string]$launcherConfig.installRoot
} else {
    $defaultInstallRoot
}
$StateRoot = if ($env:CLAWGOD_KIROCC_STATE_ROOT) {
    $env:CLAWGOD_KIROCC_STATE_ROOT
} elseif ($launcherConfig) {
    [string]$launcherConfig.stateRoot
} else {
    Join-Path $env:USERPROFILE ".clawgod-kirocc"
}
$RuntimeKind = if ($launcherConfig) { [string]$launcherConfig.runtimeKind } else { "" }
if (-not $RuntimeKind) {
    $modePath = Join-Path $InstallRoot "install-mode"
    if (Test-Path -LiteralPath $modePath -PathType Leaf) {
        $RuntimeKind = (Get-Content -LiteralPath $modePath -Raw).Trim()
    } elseif (Test-Path -LiteralPath (Join-Path $InstallRoot "clawgod\bin\clawgod.cmd")) {
        $RuntimeKind = "clawgod"
    } else {
        $RuntimeKind = "official"
    }
}
$RuntimeCommand = if ($launcherConfig) { [string]$launcherConfig.runtimeCommand } else { "" }

$GatewayPortText = if ($env:KIROCC_PORT) {
    $env:KIROCC_PORT
} elseif ($launcherConfig) {
    [string]$launcherConfig.defaultPort
} else {
    "3457"
}
$GatewayUrl = if ($env:KIROCC_URL) {
    $env:KIROCC_URL.TrimEnd('/')
} else {
    "http://127.0.0.1:$GatewayPortText"
}
$GatewayUrlLabel = if ($env:KIROCC_URL) { "<custom KIROCC_URL; value redacted>" } else { $GatewayUrl }

$passCount = 0
$warnCount = 0
$failCount = 0
function Write-Pass([string]$Message) {
    $script:passCount++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}
function Write-WarningResult([string]$Message) {
    $script:warnCount++
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}
function Write-Failure([string]$Message) {
    $script:failCount++
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}
function Test-RequiredCommand([string]$Name) {
    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        Write-Pass "command available: $Name"
    } else {
        Write-Failure "missing command: $Name"
    }
}
function Test-RequiredFile([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Write-Pass "file: $Path"
    } else {
        Write-Failure "missing file: $Path"
    }
}

Write-Host "ClaudeCode Kiro doctor for Windows (read-only)"
Write-Host "  install root: $InstallRoot"
Write-Host "  state root:   $StateRoot"
Write-Host "  runtime:      $RuntimeKind"
Write-Host "  gateway URL:  $GatewayUrlLabel"
Write-Host ""

$requiredCommands = @("go", "node")
if ($RuntimeKind -eq "clawgod") { $requiredCommands += @("bun", "rg") }
foreach ($commandName in $requiredCommands) { Test-RequiredCommand $commandName }

$officialClaude = Get-Command claude -CommandType Application,ExternalScript -ErrorAction SilentlyContinue |
    Select-Object -First 1
$isolatedLauncher = Get-Command claude-kiro -CommandType Application,ExternalScript -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($officialClaude) { Write-Pass "official Claude command: $($officialClaude.Source)" }
else { Write-Failure "official Claude command not found" }
if ($isolatedLauncher) { Write-Pass "isolated launcher: $($isolatedLauncher.Source)" }
else { Write-Failure "claude-kiro not found on PATH (expected under $UserBinDir)" }
if ($officialClaude -and $isolatedLauncher) {
    if ($officialClaude.Source -ieq $isolatedLauncher.Source) {
        Write-Failure "official claude and claude-kiro resolve to the same path"
    } else {
        Write-Pass "official claude and claude-kiro paths are separate"
    }
}

Test-RequiredFile (Join-Path $InstallRoot "bin\kirocc-native-websearch.exe")
Test-RequiredFile (Join-Path $UserBinDir "claude-kiro.cmd")
Test-RequiredFile (Join-Path $UserBinDir "claude-kiro.ps1")
Test-RequiredFile $launcherConfigPath
if ($RuntimeKind -eq "clawgod") {
    Test-RequiredFile (Join-Path $InstallRoot "clawgod\bin\clawgod.cmd")
    Test-RequiredFile (Join-Path $InstallRoot "clawgod\bin\claude.orig.exe")
    Test-RequiredFile (Join-Path $StateRoot "cli.cjs")
} elseif ($RuntimeKind -eq "official") {
    if ($RuntimeCommand -and (Test-Path -LiteralPath $RuntimeCommand -PathType Leaf)) {
        Write-Pass "official runtime target exists"
    } elseif ($officialClaude) {
        Write-WarningResult "launcher config runtime target is unavailable; reinstall to refresh the official path"
    } else {
        Write-Failure "official runtime target not found"
    }
} else {
    Write-Failure "install mode is neither official nor clawgod"
}

$settingsPath = Join-Path $StateRoot "claude-config\settings.json"
Test-RequiredFile $settingsPath
Test-RequiredFile (Join-Path $StateRoot "claude-config\CLAUDE.md")
if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    try {
        Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json | Out-Null
        Write-Pass "isolated settings.json is valid JSON"
    } catch {
        Write-Failure "isolated settings.json is invalid JSON"
    }
}

if ($env:KIRO_API_KEY) {
    Write-Pass "Kiro API-key mode selected (value redacted)"
    if ($env:KIRO_API_REGION) { Write-Pass "Kiro API region is set" }
    else { Write-WarningResult "KIRO_API_REGION is unset; gateway will default to us-east-1" }
} else {
    $databaseCandidates = if ($env:KIROCC_DB_PATH) {
        @($env:KIROCC_DB_PATH)
    } else {
        @(
            (Join-Path $env:USERPROFILE ".local\share\kiro-cli\data.sqlite3"),
            (Join-Path $env:LOCALAPPDATA "kiro-cli\data.sqlite3"),
            (Join-Path $env:APPDATA "kiro-cli\data.sqlite3")
        ) | Where-Object { $_ }
    }
    $databasePath = $databaseCandidates | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    } | Select-Object -First 1
    if ($databasePath) {
        Write-Pass "Kiro CLI database found: $databasePath"
        $kiroCli = Get-Command kiro-cli -ErrorAction SilentlyContinue
        if ($kiroCli) {
            Write-Pass "Kiro CLI command is available for login maintenance"
            & kiro-cli whoami *> $null
            if ($LASTEXITCODE -eq 0) {
                Write-Pass "kiro-cli whoami confirms a logged-in profile (output redacted)"
            } else {
                Write-Failure "kiro-cli whoami failed; run kiro-cli login, then kiro-cli whoami"
            }
        } else {
            Write-WarningResult "Kiro CLI command is missing; the gateway can use the existing database, but login repair requires Kiro CLI"
        }
    } else {
        Write-Failure "Kiro CLI database not found; set KIROCC_DB_PATH or KIRO_API_KEY"
        if (Get-Command kiro-cli -ErrorAction SilentlyContinue) {
            Write-WarningResult "run kiro-cli login, then kiro-cli whoami to create a usable login database"
        } else {
            Write-WarningResult "install Kiro CLI and log in, or set KIRO_API_KEY and KIRO_API_REGION"
        }
    }
}

$GatewayPort = 0
if (-not [int]::TryParse($GatewayPortText, [ref]$GatewayPort) -or $GatewayPort -lt 1 -or $GatewayPort -gt 65535) {
    Write-Failure "KIROCC_PORT must be between 1 and 65535"
} else {
    Write-Pass "gateway port is valid: $GatewayPort"
}
try {
    $health = Invoke-WebRequest -Uri "$GatewayUrl/health" -UseBasicParsing -TimeoutSec 1
    if ($health.StatusCode -ge 200 -and $health.StatusCode -lt 300) {
        Write-Pass "gateway health endpoint is reachable"
    } else {
        Write-WarningResult "gateway returned HTTP $($health.StatusCode)"
    }
} catch {
    Write-WarningResult "gateway is not currently reachable; this is normal when claude-kiro is closed"
}

Write-Host ""
Write-Host "Summary: $passCount pass, $warnCount warning, $failCount failure"
if ($failCount -gt 0) { exit 1 }
if ($Strict -and $warnCount -gt 0) { exit 2 }

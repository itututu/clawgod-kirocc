#Requires -Version 5.1
# ClawGod KiroCC Windows launcher. This file is copied next to
# claude-kiro.cmd and its non-secret launcher JSON by install.ps1.

$ErrorActionPreference = "Stop"

$launcherConfigPath = if ($env:CLAWGOD_KIROCC_LAUNCHER_CONFIG) {
    $env:CLAWGOD_KIROCC_LAUNCHER_CONFIG
} else {
    Join-Path $PSScriptRoot "clawgod-kirocc-launcher.json"
}

if (-not (Test-Path -LiteralPath $launcherConfigPath -PathType Leaf)) {
    Write-Error "claude-kiro: launcher config not found: $launcherConfigPath"
    exit 127
}

try {
    $launcherConfig = Get-Content -LiteralPath $launcherConfigPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "claude-kiro: invalid launcher config: $launcherConfigPath"
    exit 1
}

$installRoot = if ($env:CLAWGOD_KIROCC_INSTALL_ROOT) {
    $env:CLAWGOD_KIROCC_INSTALL_ROOT
} else {
    [string]$launcherConfig.installRoot
}
$stateRoot = if ($env:CLAWGOD_KIROCC_STATE_ROOT) {
    $env:CLAWGOD_KIROCC_STATE_ROOT
} else {
    [string]$launcherConfig.stateRoot
}
$configDir = if ($env:CLAUDE_KIRO_CONFIG_DIR) {
    $env:CLAUDE_KIRO_CONFIG_DIR
} elseif ($env:CLAWGOD_KIROCC_CONFIG_DIR) {
    $env:CLAWGOD_KIROCC_CONFIG_DIR
} else {
    Join-Path $stateRoot "claude-config"
}
$gatewayBin = if ($env:KIROCC_BIN) {
    $env:KIROCC_BIN
} else {
    Join-Path $installRoot "bin\kirocc-native-websearch.exe"
}
$runtimeKind = [string]$launcherConfig.runtimeKind
$runtimeBin = if ($env:CLAUDE_KIRO_RUNTIME_BIN) {
    $env:CLAUDE_KIRO_RUNTIME_BIN
} elseif ($env:CLAWGOD_BIN) {
    $env:CLAWGOD_BIN
} else {
    [string]$launcherConfig.runtimeCommand
}
$gatewayPortText = if ($env:KIROCC_PORT) {
    $env:KIROCC_PORT
} else {
    [string]$launcherConfig.defaultPort
}

$gatewayPort = 0
if (-not [int]::TryParse($gatewayPortText, [ref]$gatewayPort) -or $gatewayPort -lt 1 -or $gatewayPort -gt 65535) {
    Write-Error "claude-kiro: KIROCC_PORT must be between 1 and 65535"
    exit 2
}

$gatewayUrl = if ($env:KIROCC_URL) {
    $env:KIROCC_URL.TrimEnd('/')
} else {
    "http://127.0.0.1:$gatewayPort"
}
$proxyToken = if ($env:KIROCC_API_KEY) { $env:KIROCC_API_KEY } else { "dummy" }

if ($args.Count -gt 0 -and $args[0] -eq "update") {
    Write-Error "claude-kiro: updates are disabled in the isolated profile; rerun the project installer"
    exit 2
}
if (-not (Test-Path -LiteralPath $gatewayBin -PathType Leaf)) {
    Write-Error "claude-kiro: gateway not found: $gatewayBin"
    exit 127
}
if (-not (Test-Path -LiteralPath $runtimeBin -PathType Leaf)) {
    Write-Error "claude-kiro: $runtimeKind runtime not found: $runtimeBin"
    exit 127
}

function Test-GatewayHealth {
    try {
        $response = Invoke-WebRequest -Uri "$gatewayUrl/health" -UseBasicParsing -TimeoutSec 1
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 300
    } catch {
        return $false
    }
}

function Test-GatewayAccess {
    try {
        $headers = @{ Authorization = "Bearer $proxyToken" }
        $response = Invoke-WebRequest -Uri "$gatewayUrl/v1/models" -Headers $headers -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -ge 200 -and $response.StatusCode -lt 300
    } catch {
        return $false
    }
}

function Set-LocalKiroCredentialSource {
    if ($env:KIRO_API_KEY) { return }

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
        $env:KIROCC_DB_PATH = $databasePath
        return
    }

    $expectedDatabase = if ($databaseCandidates.Count -gt 0) {
        $databaseCandidates -join "; "
    } else {
        "<no database candidate>"
    }
    Write-Error @"
claude-kiro: no usable Kiro credential source was found.
Kiro CLI is only needed to create the login credential; traffic is sent by the
kirocc gateway itself.

Install/login Kiro CLI:
  irm 'https://cli.kiro.dev/install.ps1' | iex
  kiro-cli login
  kiro-cli whoami

Or set KIRO_API_KEY (and optionally KIRO_API_REGION) before launching.
Expected database: $expectedDatabase
"@
    exit 78
}

$startedGateway = $null
$logBase = Join-Path $env:TEMP "clawgod-kirocc-gateway-$PID-$gatewayPort"
$stdoutLog = "$logBase.out.log"
$stderrLog = "$logBase.err.log"

try {
    $gatewayHealthy = Test-GatewayHealth
    if ($gatewayHealthy -and -not (Test-GatewayAccess)) {
        Write-Error "claude-kiro: a gateway is already running at $gatewayUrl but rejects the current KIROCC_API_KEY. Use the matching local proxy key or choose an unused port, for example: `$env:KIROCC_PORT='3458'; claude-kiro"
        exit 1
    }
    if (-not $gatewayHealthy) {
        Set-LocalKiroCredentialSource
        $startedGateway = Start-Process -FilePath $gatewayBin `
            -ArgumentList @("-port", "$gatewayPort") `
            -RedirectStandardOutput $stdoutLog `
            -RedirectStandardError $stderrLog `
            -WindowStyle Hidden `
            -PassThru

        $ready = $false
        for ($attempt = 0; $attempt -lt 50; $attempt++) {
            if (Test-GatewayHealth) {
                $ready = $true
                break
            }
            if ($startedGateway.HasExited) { break }
            Start-Sleep -Milliseconds 100
        }
        if (-not $ready) {
            Write-Error "claude-kiro: gateway failed to start"
            foreach ($logPath in @($stderrLog, $stdoutLog)) {
                if (Test-Path -LiteralPath $logPath -PathType Leaf) {
                    Write-Host "--- $logPath ---" -ForegroundColor DarkGray
                    Get-Content -LiteralPath $logPath -Tail 40 -ErrorAction SilentlyContinue |
                        ForEach-Object { Write-Host $_ }
                }
            }
            exit 1
        }
        if (-not (Test-GatewayAccess)) {
            Write-Error "claude-kiro: gateway started but rejected the configured local proxy key"
            exit 1
        }
    }

    # This launcher runs in its own PowerShell process, so these environment
    # changes are inherited only by ClawGod and its children.
    foreach ($name in @(
        "ANTHROPIC_API_KEY",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY"
    )) {
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    $env:CLAWGOD_RUNTIME_STATE_ROOT = $stateRoot
    $env:CLAUDE_CONFIG_DIR = $configDir
    $env:ANTHROPIC_BASE_URL = $gatewayUrl
    $env:ANTHROPIC_AUTH_TOKEN = $proxyToken

    & $runtimeBin @args
    $claudeExitCode = $LASTEXITCODE
    if ($null -eq $claudeExitCode) { $claudeExitCode = 0 }
    exit $claudeExitCode
} finally {
    if ($startedGateway -and -not $startedGateway.HasExited) {
        Stop-Process -Id $startedGateway.Id -Force -ErrorAction SilentlyContinue
        $startedGateway.WaitForExit(5000) | Out-Null
    }
}

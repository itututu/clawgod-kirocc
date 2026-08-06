#Requires -Version 5.1
# ClaudeCode Kiro Windows launcher. This file is copied next to
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
try {
    $gatewayUri = [Uri]$gatewayUrl
} catch {
    Write-Error "claude-kiro: KIROCC_URL is not a valid URL: $gatewayUrl"
    exit 2
}
$gatewayIsLoopback = $gatewayUri.IsLoopback
$proxyToken = if ($env:KIROCC_API_KEY) { $env:KIROCC_API_KEY } else { "dummy" }

# The region stored by kiro-cli is the login region, but Kiro inference is not
# served in every AWS region. Pin managed gateway traffic to a known runtime by
# default. Users closer to Europe can override this before launching.
if (-not $env:KIRO_API_REGION) {
    $env:KIRO_API_REGION = "us-east-1"
}

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

function Invoke-GatewayProbe([string]$Path, [bool]$WithAuthorization, [int]$TimeoutMilliseconds) {
    try {
        $request = [System.Net.WebRequest]::Create("$gatewayUrl$Path")
        $request.Method = "GET"
        $request.Timeout = $TimeoutMilliseconds
        $request.ReadWriteTimeout = $TimeoutMilliseconds
        if ($gatewayIsLoopback) {
            # Do not let Windows/user proxy settings intercept health checks to
            # the managed loopback gateway.
            $request.Proxy = $null
        }
        if ($WithAuthorization) {
            $request.Headers.Add("Authorization", "Bearer $proxyToken")
        }
        $response = $request.GetResponse()
        try {
            $statusCode = [int]$response.StatusCode
            return $statusCode -ge 200 -and $statusCode -lt 300
        } finally {
            $response.Close()
        }
    } catch {
        return $false
    }
}

function Test-GatewayHealth {
    return Invoke-GatewayProbe -Path "/health" -WithAuthorization $false -TimeoutMilliseconds 1000
}

function Test-GatewayAccess {
    return Invoke-GatewayProbe -Path "/v1/models" -WithAuthorization $true -TimeoutMilliseconds 2000
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
Managed default: KIRO_API_REGION=us-east-1 (eu-central-1 is also supported).
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

    # The gateway process was started above and already inherited the user's
    # proxy variables for reaching Kiro. Claude Code itself must reach a local
    # gateway directly: current Claude Code proxy handling does not reliably
    # honor NO_PROXY for loopback URLs, which can send 127.0.0.1 through an
    # HTTP proxy and surface a bodyless 502 without ever touching this gateway.
    # This launcher has its own PowerShell process, so removing variables here
    # does not alter the user's terminal environment.
    $runtimeUnsetNames = @(
        "ANTHROPIC_API_KEY",
        "CLAUDE_CODE_OAUTH_TOKEN",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_VERTEX",
        "CLAUDE_CODE_USE_FOUNDRY"
    )
    if ($gatewayIsLoopback -and $env:CLAUDE_KIRO_PRESERVE_PROXY -ne "1") {
        $runtimeUnsetNames += @(
            "HTTP_PROXY",
            "HTTPS_PROXY",
            "ALL_PROXY",
            "http_proxy",
            "https_proxy",
            "all_proxy"
        )
    }
    foreach ($name in ($runtimeUnsetNames | Select-Object -Unique)) {
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

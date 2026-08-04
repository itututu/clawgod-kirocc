#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$WithClawGod,
    [switch]$RefreshClawGod,
    [switch]$GatewayOnly,
    [switch]$Help
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Get-EnvOrDefault([string]$Name, [string]$DefaultValue) {
    $value = [Environment]::GetEnvironmentVariable($Name, "Process")
    if ($value) { return $value }
    return $DefaultValue
}

function Write-Usage {
    @"
Usage: .\scripts\install.ps1 [-WithClawGod] [-RefreshClawGod] [-GatewayOnly]

  Default           Install KiroCC + isolated claude-kiro using official Claude Code.
  -WithClawGod      Also generate the isolated ClawGod runtime (opt-in).
  -RefreshClawGod   Rebuild ClawGod and implies -WithClawGod.
  -GatewayOnly      Use an existing CLAWGOD_BIN and implies -WithClawGod.

Environment overrides:
  CLAWGOD_BIN
  CLAWGOD_RELEASE
  CLAWGOD_INSTALLER_SHA256
  CLAWGOD_KIROCC_INSTALL_ROOT
  CLAWGOD_KIROCC_STATE_ROOT
  CLAWGOD_KIROCC_BIN_DIR
  KIROCC_PORT
  KIROCC_DB_PATH
  KIRO_API_KEY       Kiro upstream API key; makes Kiro CLI optional.
  KIRO_API_REGION
"@ | Write-Host
}

if ($Help) {
    Write-Usage
    exit 0
}
if ($RefreshClawGod -or $GatewayOnly) { $WithClawGod = $true }
if ($GatewayOnly -and -not $env:CLAWGOD_BIN) {
    throw "CLAWGOD_BIN is required with -GatewayOnly"
}

$defaultInstallRoot = Join-Path $env:LOCALAPPDATA "ClawGodKiroCC\clawgod-kirocc"
$InstallRoot = Get-EnvOrDefault "CLAWGOD_KIROCC_INSTALL_ROOT" $defaultInstallRoot
$StateRoot = Get-EnvOrDefault "CLAWGOD_KIROCC_STATE_ROOT" (Join-Path $env:USERPROFILE ".clawgod-kirocc")
$UserBinDir = Get-EnvOrDefault "CLAWGOD_KIROCC_BIN_DIR" (Join-Path $env:USERPROFILE ".local\bin")
$GatewayPortText = Get-EnvOrDefault "KIROCC_PORT" "3457"
$ClawGodRelease = Get-EnvOrDefault "CLAWGOD_RELEASE" "v1.7.5"
$PinnedClawGodHash = "bf2a9947f5f5747ceaf0ebc77f8f0c66887a2c390e7e996c28b6c72b5b579d3e"
$ClawGodInstallerHash = Get-EnvOrDefault "CLAWGOD_INSTALLER_SHA256" $PinnedClawGodHash

$GatewayPort = 0
if (-not [int]::TryParse($GatewayPortText, [ref]$GatewayPort) -or $GatewayPort -lt 1 -or $GatewayPort -gt 65535) {
    throw "KIROCC_PORT must be between 1 and 65535"
}
if ($WithClawGod -and $ClawGodRelease -ne "v1.7.5" -and -not $env:CLAWGOD_INSTALLER_SHA256) {
    throw "CLAWGOD_INSTALLER_SHA256 is required for ClawGod releases other than v1.7.5"
}

$requiredCommands = @("go", "node")
if ($WithClawGod) { $requiredCommands += @("bun", "rg") }
foreach ($commandName in $requiredCommands) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "missing prerequisite: $commandName"
    }
}

$OfficialClaudeCommand = Get-Command claude -CommandType Application,ExternalScript -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $OfficialClaudeCommand) {
    throw "official Claude Code command not found"
}
$OfficialClaudePath = if ($OfficialClaudeCommand.Path) {
    $OfficialClaudeCommand.Path
} else {
    $OfficialClaudeCommand.Source
}
$officialDirectory = Split-Path -Parent $OfficialClaudePath
$officialExtension = [IO.Path]::GetExtension($OfficialClaudePath)
$officialBaseName = [IO.Path]::GetFileNameWithoutExtension($OfficialClaudePath)
$officialBackup = Join-Path $officialDirectory "$officialBaseName.orig$officialExtension"
if (Test-Path -LiteralPath $officialBackup -PathType Leaf) {
    $OfficialClaudePath = $officialBackup
}
$OfficialClaudePath = [IO.Path]::GetFullPath($OfficialClaudePath)
$OfficialClaudeHash = (Get-FileHash -LiteralPath $OfficialClaudePath -Algorithm SHA256).Hash

$kiroDatabaseCandidates = if ($env:KIROCC_DB_PATH) {
    @($env:KIROCC_DB_PATH)
} else {
    @(
        (Join-Path $env:USERPROFILE ".local\share\kiro-cli\data.sqlite3"),
        (Join-Path $env:LOCALAPPDATA "kiro-cli\data.sqlite3"),
        (Join-Path $env:APPDATA "kiro-cli\data.sqlite3")
    ) | Where-Object { $_ }
}
$kiroDatabasePath = $kiroDatabaseCandidates | Where-Object {
    Test-Path -LiteralPath $_ -PathType Leaf
} | Select-Object -First 1
if ($env:KIRO_API_KEY) {
    Write-Host "Kiro authentication: API-key mode (Kiro CLI is not required)."
} elseif ($kiroDatabasePath) {
    $kiroCli = Get-Command kiro-cli -ErrorAction SilentlyContinue
    if ($kiroCli) {
        & kiro-cli whoami *> $null
        if ($LASTEXITCODE -ne 0) {
            throw @"
Kiro CLI database exists, but kiro-cli whoami did not confirm a logged-in profile.
Run:

  kiro-cli login
  kiro-cli whoami

Then rerun this installer. Request traffic will still be sent directly by the
kirocc gateway; this check only validates the credential it will read.
"@
        }
        Write-Host "Kiro authentication: existing login confirmed (whoami output redacted)."
    } else {
        Write-Host "Kiro authentication: existing login database found (Kiro CLI command unavailable; live status not checked)."
    }
} else {
    $kiroCliState = if (Get-Command kiro-cli -ErrorAction SilentlyContinue) {
        "Kiro CLI is installed, but its login database was not found."
    } else {
        "Kiro CLI is not installed and no existing login database was found."
    }
    $expectedDatabase = if ($kiroDatabaseCandidates.Count -gt 0) {
        $kiroDatabaseCandidates -join "; "
    } else {
        "<no database candidate>"
    }
    throw @"
No usable Kiro credential source found.
$kiroCliState

Kiro CLI is used only to create the local login credential; request traffic is
sent directly by the kirocc gateway. Install/login with:

  irm 'https://cli.kiro.dev/install.ps1' | iex
  kiro-cli login
  kiro-cli whoami

Or set KIRO_API_KEY (and optionally KIRO_API_REGION) before running this
installer and whenever claude-kiro is launched.
Expected database: $expectedDatabase
"@
}

New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "bin") | Out-Null
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $StateRoot "claude-config") | Out-Null
New-Item -ItemType Directory -Force -Path $UserBinDir | Out-Null
if ($WithClawGod) {
    New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot "clawgod\bin") | Out-Null
}

$TemporaryRoot = Join-Path $env:TEMP "clawgod-kirocc-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $TemporaryRoot | Out-Null

try {
    Write-Host "Building patched kirocc..."
    $temporaryGateway = Join-Path $TemporaryRoot "kirocc-native-websearch.exe"
    $oldGoExperiment = $env:GOEXPERIMENT
    try {
        $env:GOEXPERIMENT = "jsonv2"
        & go build -trimpath -o $temporaryGateway (Join-Path $ProjectRoot "cmd\kirocc")
        if ($LASTEXITCODE -ne 0) { throw "go build failed with exit code $LASTEXITCODE" }
    } finally {
        $env:GOEXPERIMENT = $oldGoExperiment
    }
    $installedGateway = Join-Path $InstallRoot "bin\kirocc-native-websearch.exe"
    Copy-Item -LiteralPath $temporaryGateway -Destination $installedGateway -Force

    $RuntimeKind = "official"
    $RuntimeCommand = $OfficialClaudePath
    $isolatedClawGod = if ($env:CLAWGOD_BIN) {
        $env:CLAWGOD_BIN
    } else {
        Join-Path $InstallRoot "clawgod\bin\clawgod.cmd"
    }

    if ($WithClawGod -and -not $GatewayOnly -and ($RefreshClawGod -or -not (Test-Path -LiteralPath $isolatedClawGod -PathType Leaf))) {
        $clawGodInstaller = Join-Path $TemporaryRoot "clawgod-install.ps1"
        $clawGodUrl = "https://github.com/0Chencc/clawgod/releases/download/$ClawGodRelease/install.ps1"
        Write-Host "Downloading ClawGod $ClawGodRelease Windows installer..."
        Invoke-WebRequest -Uri $clawGodUrl -OutFile $clawGodInstaller -UseBasicParsing
        $actualHash = (Get-FileHash -LiteralPath $clawGodInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $ClawGodInstallerHash.ToLowerInvariant()) {
            throw "ClawGod installer checksum mismatch. Expected $ClawGodInstallerHash; actual $actualHash"
        }

        # Add opt-in path overrides to the downloaded GPL installer. The
        # modified copy is temporary and its generated files stay isolated.
        $source = Get-Content -LiteralPath $clawGodInstaller -Raw
        $replacementPairs = @(
            @('$ClawDir = Join-Path $env:USERPROFILE ".clawgod"', '$ClawDir = if ($env:CLAWGOD_DIR_OVERRIDE) { $env:CLAWGOD_DIR_OVERRIDE } else { Join-Path $env:USERPROFILE ".clawgod" }'),
            @('$BinDir  = Join-Path $env:USERPROFILE ".local\bin"', '$BinDir = if ($env:CLAWGOD_BIN_DIR_OVERRIDE) { $env:CLAWGOD_BIN_DIR_OVERRIDE } else { Join-Path $env:USERPROFILE ".local\bin" }'),
            @('$claudeSettingsDir = Join-Path $env:USERPROFILE ".claude"', '$claudeSettingsDir = if ($env:CLAWGOD_CLAUDE_SETTINGS_DIR_OVERRIDE) { $env:CLAWGOD_CLAUDE_SETTINGS_DIR_OVERRIDE } else { Join-Path $env:USERPROFILE ".claude" }'),
            @('const clawgodDir = join(homedir(), ''.clawgod'');', 'const clawgodDir = process.env.CLAWGOD_RUNTIME_STATE_ROOT || join(homedir(), ''.clawgod'');'),
            @('const nativeClaudeJson = join(homedir(), ''.claude.json'');', 'const nativeClaudeJson = join(process.env.CLAUDE_CONFIG_DIR || homedir(), ''.claude.json'');'),
            @('const _rcSettings = join(homedir(), ''.claude'', ''settings.json'');', 'const _rcSettings = process.env.CLAUDE_CONFIG_DIR ? join(process.env.CLAUDE_CONFIG_DIR, ''settings.json'') : join(homedir(), ''.claude'', ''settings.json'');'),
            @('const _leanSettings = join(homedir(), ''.claude'', ''settings.json'');', 'const _leanSettings = process.env.CLAUDE_CONFIG_DIR ? join(process.env.CLAUDE_CONFIG_DIR, ''settings.json'') : join(homedir(), ''.claude'', ''settings.json'');'),
            @('$cliPathInCmd = "%USERPROFILE%\.clawgod\cli.cjs"', '$cliPathInCmd = Join-Path $ClawDir "cli.cjs"'),
            @('$importPathInCmd = "%USERPROFILE%\.clawgod\clawgod-import.exe"', '$importPathInCmd = Join-Path $ClawDir "clawgod-import.exe"'),
            @('if ($userPath -notlike "*$BinDir*") {', 'if ($env:CLAWGOD_SKIP_PATH_UPDATE -ne "1" -and $userPath -notlike "*$BinDir*") {')
        )
        foreach ($pair in $replacementPairs) {
            $before = [string]$pair[0]
            $after = [string]$pair[1]
            if (-not $source.Contains($before)) {
                throw "unsupported ClawGod Windows installer: missing marker $before"
            }
            $source = $source.Replace($before, $after)
        }
        $nativeBackupNeedle = '$claudeOrigExe = Join-Path $BinDir "claude.orig.exe"'
        $nativeBackupReplacement = @'
$claudeOrigExe = Join-Path $BinDir "claude.orig.exe"
if (-not (Test-Path $claudeOrigExe) -and $NativeBin -and (Test-Path $NativeBin)) {
    Copy-Item $NativeBin $claudeOrigExe -Force
    Write-OK "Isolated original Claude binary created"
}
'@
        if (-not $source.Contains($nativeBackupNeedle)) {
            throw "unsupported ClawGod Windows installer: original binary marker missing"
        }
        $source = $source.Replace($nativeBackupNeedle, $nativeBackupReplacement.TrimEnd())
        Set-Content -LiteralPath $clawGodInstaller -Value $source -Encoding UTF8

        $isolatedClawBinDir = Join-Path $InstallRoot "clawgod\bin"
        $isolatedConfigDir = Join-Path $StateRoot "claude-config"
        $overrideNames = @(
            "CLAWGOD_DIR_OVERRIDE",
            "CLAWGOD_BIN_DIR_OVERRIDE",
            "CLAWGOD_CLAUDE_SETTINGS_DIR_OVERRIDE",
            "CLAWGOD_RUNTIME_STATE_ROOT",
            "CLAWGOD_SKIP_PATH_UPDATE",
            "CLAUDE_CONFIG_DIR"
        )
        $previousValues = @{}
        foreach ($name in $overrideNames) {
            $previousValues[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
        }
        try {
            $env:CLAWGOD_DIR_OVERRIDE = $StateRoot
            $env:CLAWGOD_BIN_DIR_OVERRIDE = $isolatedClawBinDir
            $env:CLAWGOD_CLAUDE_SETTINGS_DIR_OVERRIDE = $isolatedConfigDir
            $env:CLAWGOD_RUNTIME_STATE_ROOT = $StateRoot
            $env:CLAWGOD_SKIP_PATH_UPDATE = "1"
            $env:CLAUDE_CONFIG_DIR = $isolatedConfigDir
            $windowsPowerShell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
            & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $clawGodInstaller -LeanOff
            if ($LASTEXITCODE -ne 0) { throw "ClawGod installer failed with exit code $LASTEXITCODE" }
        } finally {
            foreach ($name in $overrideNames) {
                [Environment]::SetEnvironmentVariable($name, $previousValues[$name], "Process")
            }
        }
        $isolatedClawGod = Join-Path $isolatedClawBinDir "clawgod.cmd"
    }

    if ($WithClawGod) {
        if (-not (Test-Path -LiteralPath $isolatedClawGod -PathType Leaf)) {
            throw "ClawGod launcher not found: $isolatedClawGod"
        }
        $RuntimeKind = "clawgod"
        $RuntimeCommand = [IO.Path]::GetFullPath($isolatedClawGod)
    }

    $isolatedConfigDir = Join-Path $StateRoot "claude-config"
    foreach ($configName in @("CLAUDE.md", "settings.json")) {
        $destination = Join-Path $isolatedConfigDir $configName
        if (-not (Test-Path -LiteralPath $destination)) {
            Copy-Item -LiteralPath (Join-Path $ProjectRoot "config\$configName") -Destination $destination
        }
    }

    $launcherScript = Join-Path $UserBinDir "claude-kiro.ps1"
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "windows\claude-kiro.ps1") -Destination $launcherScript -Force
    $launcherConfig = [ordered]@{
        schemaVersion = 1
        installRoot = [IO.Path]::GetFullPath($InstallRoot)
        stateRoot = [IO.Path]::GetFullPath($StateRoot)
        defaultPort = $GatewayPort
        runtimeKind = $RuntimeKind
        runtimeCommand = $RuntimeCommand
    }
    $launcherConfig | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $UserBinDir "clawgod-kirocc-launcher.json") -Encoding UTF8
    $launcherCmd = @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-kiro.ps1" %*
exit /b %ERRORLEVEL%
'@
    Set-Content -LiteralPath (Join-Path $UserBinDir "claude-kiro.cmd") -Value $launcherCmd.TrimEnd() -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $InstallRoot "install-mode") -Value $RuntimeKind -Encoding ASCII

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = @($userPath -split ';' | Where-Object { $_ })
    if (-not ($pathEntries | Where-Object { $_.TrimEnd('\') -ieq $UserBinDir.TrimEnd('\') })) {
        $newUserPath = if ($userPath) { "$UserBinDir;$userPath" } else { $UserBinDir }
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    }
    if (-not (($env:Path -split ';') | Where-Object { $_.TrimEnd('\') -ieq $UserBinDir.TrimEnd('\') })) {
        $env:Path = "$UserBinDir;$env:Path"
    }

    $officialAfter = (Get-FileHash -LiteralPath $OfficialClaudePath -Algorithm SHA256).Hash
    if ($officialAfter -ne $OfficialClaudeHash) {
        throw "official Claude Code changed during installation; refusing to report success"
    }

    Write-Host ""
    Write-Host "Installed successfully:" -ForegroundColor Green
    Write-Host "  launcher: $(Join-Path $UserBinDir 'claude-kiro.cmd')"
    Write-Host "  gateway:  $installedGateway"
    Write-Host "  runtime:  $RuntimeCommand ($RuntimeKind)"
    Write-Host "  config:   $isolatedConfigDir"
    Write-Host ""
    Write-Host "The official claude command was not modified by this installer."
} finally {
    Remove-Item -LiteralPath $TemporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}

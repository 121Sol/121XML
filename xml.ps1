<#
121XML website/API deployment automation.

  .\xml.ps1 help                Show this help
  .\xml.ps1 backup  <target>    Download a full copy of the remote web root
  .\xml.ps1 deploy  <target>    Deploy content to target (staging or production)
  .\xml.ps1 rollback <target>   Restore the latest backup of that target
  .\xml.ps1 smoke   <target>    Check the live site is responding

  Target: staging or production
#>

param(
    [Parameter(Position = 0)][string]$Cmd = "help",
    [Parameter(Position = 1)][string]$Target = "",
    [Parameter(Position = 2)][string]$Extra = ""
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Color output helpers
function Step($m) { Write-Host "`n== $m" -ForegroundColor DarkYellow }
function Success($m) { Write-Host "✓ $m" -ForegroundColor Green }
function Error($m) { Write-Host "✗ $m" -ForegroundColor Red }
function Warn($m) { Write-Host "⚠ $m" -ForegroundColor Yellow }
function Info($m) { Write-Host "ℹ $m" -ForegroundColor Cyan }

function Run {
    & $args[0] $args[1..($args.Count - 1)]
    if ($LASTEXITCODE -ne 0) {
        throw "Failed: $($args -join ' ')"
    }
}

function Need-Target {
    if ($Target -notin @("staging", "production")) {
        throw "Specify target: staging or production"
    }
}

function Need-Env {
    if (-not (Test-Path .env)) {
        throw "Missing .env. Copy .env.example to .env and fill in SSH host, user, key path and target paths."
    }
}

# Load environment variables from .env
function Load-Env {
    if (Test-Path .env) {
        Get-Content .env | ForEach-Object {
            if ($_ -match '^\s*([^=]+)=(.*)$') {
                $name = $matches[1].Trim()
                $value = $matches[2].Trim()
                if ($value -match '^"(.*)"$') { $value = $matches[1] }
                [Environment]::SetEnvironmentVariable($name, $value, "Process")
            }
        }
    }
}

# SSH command helper
function SSH-Cmd {
    param(
        [string]$Cmd,
        [string]$Host = $env:XML_SSH_HOST,
        [string]$Port = $env:XML_SSH_PORT,
        [string]$User = $env:XML_SSH_USER,
        [string]$KeyPath = $env:XML_SSH_KEY
    )

    if (-not (Test-Path $KeyPath)) {
        throw "SSH key not found: $KeyPath"
    }

    $sshArgs = @(
        "-i", $KeyPath,
        "-p", $Port,
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=10",
        "$User@$Host",
        $Cmd
    )

    ssh @sshArgs
}

# Verify SSH connection
function Test-SSHConnection {
    Step "Testing SSH connection..."
    try {
        $result = SSH-Cmd "echo 'SSH connection successful'"
        if ($LASTEXITCODE -eq 0) {
            Success "SSH connection verified"
            return $true
        } else {
            Error "SSH connection test failed"
            return $false
        }
    } catch {
        Error "SSH error: $_"
        return $false
    }
}

# Backup command
function Backup-Remote {
    Need-Target
    Need-Env
    Load-Env

    Step "Backing up $Target..."

    if ($Target -eq "staging") {
        $remotePath = $env:XML_STAGING_PATH
    } else {
        $remotePath = $env:XML_PROD_PATH
    }

    if (-not (Test-Path "backups")) {
        New-Item -ItemType Directory -Path "backups" -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupFile = "backups\${Target}-backup-${timestamp}.tar.gz"

    Info "Backing up $remotePath to $backupFile..."

    # Create tar backup via SSH
    $sshCmd = "tar -czf - -C '$remotePath' ."
    ssh -i $env:XML_SSH_KEY -p $env:XML_SSH_PORT `
        -o StrictHostKeyChecking=accept-new `
        -o BatchMode=yes `
        "$($env:XML_SSH_USER)@$($env:XML_SSH_HOST)" `
        $sshCmd | Set-Content -Path $backupFile -AsByteStream

    if (Test-Path $backupFile) {
        $size = (Get-Item $backupFile).Length / 1MB
        Success "Backup saved: $backupFile ($([Math]::Round($size, 2)) MB)"
    } else {
        throw "Backup file was not created"
    }
}

# Deploy command
function Deploy-Content {
    Need-Target
    Need-Env
    Load-Env

    Step "Deploying to $Target..."

    # First backup
    Backup-Remote

    if ($Target -eq "staging") {
        $remotePath = $env:XML_STAGING_PATH
        $url = $env:XML_STAGING_URL
    } else {
        $remotePath = $env:XML_PROD_PATH
        $url = $env:XML_PROD_URL
    }

    Info "Syncing content to $remotePath..."

    # Sync current directory to remote
    # Note: rsync may need to be installed; PowerShell version uses scp as fallback
    $contentDir = "content"
    if (Test-Path $contentDir) {
        # Use tar via SSH as a portable solution
        tar -czf - -C $contentDir . | `
            ssh -i $env:XML_SSH_KEY -p $env:XML_SSH_PORT `
                -o StrictHostKeyChecking=accept-new `
                -o BatchMode=yes `
                "$($env:XML_SSH_USER)@$($env:XML_SSH_HOST)" `
                "tar -xzf - -C '$remotePath'"

        if ($LASTEXITCODE -ne 0) {
            throw "Deployment failed"
        }

        Success "Content deployed to $Target"
    } else {
        throw "Content directory not found: $contentDir"
    }

    # Run smoke test
    Smoke-Test
}

# Smoke test command
function Smoke-Test {
    param($testTarget = $Target)

    if ($testTarget -eq "staging") {
        $url = $env:XML_STAGING_URL
    } else {
        $url = $env:XML_PROD_URL
    }

    Step "Running smoke test on $url..."

    $testPaths = @("/", "/sitemap.xml", "/robots.txt")
    $failed = 0

    foreach ($path in $testPaths) {
        try {
            $response = Invoke-WebRequest -Uri "$url$path" -TimeoutSec 10 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                Success "OK $($response.StatusCode) $path"
            } else {
                Error "HTTP $($response.StatusCode) $path"
                $failed++
            }
        } catch {
            Error "Failed to fetch $path : $_"
            $failed++
        }
    }

    if ($failed -gt 0) {
        throw "$failed smoke test(s) failed"
    } else {
        Success "All smoke tests passed"
    }
}

# Rollback command
function Rollback-To {
    Need-Target
    Need-Env
    Load-Env

    Step "Rolling back $Target..."

    $backupFile = $Extra
    if (-not $backupFile) {
        # Find latest backup
        $backupFile = Get-ChildItem "backups\${Target}-backup-*.tar.gz" |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $backupFile -or -not (Test-Path $backupFile)) {
        throw "No backup file found for $Target"
    }

    if ($Target -eq "staging") {
        $remotePath = $env:XML_STAGING_PATH
    } else {
        $remotePath = $env:XML_PROD_PATH
    }

    Info "Restoring from $backupFile to $remotePath..."

    # Restore via SSH
    cat $backupFile | `
        ssh -i $env:XML_SSH_KEY -p $env:XML_SSH_PORT `
            -o StrictHostKeyChecking=accept-new `
            -o BatchMode=yes `
            "$($env:XML_SSH_USER)@$($env:XML_SSH_HOST)" `
            "tar -xzf - -C '$remotePath'"

    if ($LASTEXITCODE -ne 0) {
        throw "Rollback failed"
    }

    Success "Rollback complete"

    # Run smoke test
    Smoke-Test
}

# Main command dispatcher
switch ($Cmd.ToLower()) {
    "help" {
        Get-Help $PSCommandPath -Detailed | Out-String | Write-Host
    }
    "backup" {
        Backup-Remote
    }
    "deploy" {
        Deploy-Content
    }
    "rollback" {
        Rollback-To
    }
    "smoke" {
        Need-Target
        Need-Env
        Load-Env
        Smoke-Test
    }
    default {
        Write-Host "Unknown command: $Cmd`n"
        Get-Help $PSCommandPath -Detailed | Out-String | Write-Host
        exit 1
    }
}

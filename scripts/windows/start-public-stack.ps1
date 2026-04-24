$ErrorActionPreference = "Stop"

function Stop-ProcessesByPattern {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Pattern
  )

  Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -and $_.CommandLine -match $Pattern } |
    ForEach-Object {
      try {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
      } catch {
        Write-Warning ("Stop process failed PID={0}: {1}" -f $_.ProcessId, $_.Exception.Message)
      }
    }
}

function Require-Path {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "$Label missing: $Path"
  }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dashboardDir = Join-Path $repoRoot "dashboard"
$tmpDir = Join-Path $repoRoot "tmp"
$configPath = Join-Path $env:APPDATA "ClawOSS\public-stack.json"
$dashboardStdout = Join-Path $tmpDir "dashboard-start.out.log"
$dashboardStderr = Join-Path $tmpDir "dashboard-start.err.log"
$cloudflaredLog = Join-Path $tmpDir "cloudflared.log"
$cloudflaredPid = Join-Path $tmpDir "cloudflared.pid"
$powershellExe = "C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe"

Require-Path -Path $configPath -Label "public stack config"

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$npxCmd = if ($config.npxPath) { [string]$config.npxPath } else { "D:\develop\qianduan_tool\npx.cmd" }
$cloudflaredExe = if ($config.cloudflaredPath) { [string]$config.cloudflaredPath } else { "C:\Program Files (x86)\cloudflared\cloudflared.exe" }
$dashboardPort = if ($config.dashboardPort) { [int]$config.dashboardPort } else { 3000 }
$dashboardHost = if ($config.dashboardHost) { [string]$config.dashboardHost } else { "0.0.0.0" }
$databaseUrl = if ($config.databaseUrl) { [string]$config.databaseUrl } else { "file:demo-local.db" }
$clawAgentUsername = if ($config.clawAgentUsername) { [string]$config.clawAgentUsername } elseif ($config.githubUsername) { [string]$config.githubUsername } else { "clawoss-agent" }
$manualGithubSync = if ($null -ne $config.manualGithubSync) { [bool]$config.manualGithubSync } else { $false }
$autoGithubSync = if ($null -ne $config.autoGithubSync) { [bool]$config.autoGithubSync } else { $false }
$manualGithubSyncEnv = if ($manualGithubSync) { "true" } else { "false" }
$autoGithubSyncEnv = if ($autoGithubSync) { "true" } else { "false" }

Require-Path -Path $npxCmd -Label "npx"
Require-Path -Path $cloudflaredExe -Label "cloudflared"

New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

Stop-ProcessesByPattern -Pattern ([regex]::Escape($dashboardDir))
Get-Process cloudflared -ErrorAction SilentlyContinue | ForEach-Object {
  try {
    Stop-Process -Id $_.Id -Force -ErrorAction Stop
  } catch {
    Write-Warning ("Stop cloudflared failed PID={0}: {1}" -f $_.Id, $_.Exception.Message)
  }
}

if (Test-Path -LiteralPath $cloudflaredPid) {
  Remove-Item -LiteralPath $cloudflaredPid -Force -ErrorAction SilentlyContinue
}

$dashboardCommand = @(
  "`$env:GITHUB_TOKEN='$($config.githubToken)'"
  "`$env:CLAW_AGENT_USERNAME='$clawAgentUsername'"
  "`$env:CLAW_API_KEY='$($config.clawApiKey)'"
  "`$env:TURSO_DATABASE_URL='$databaseUrl'"
  "`$env:CLAWOSS_DASHBOARD_MANUAL_GITHUB_SYNC='$manualGithubSyncEnv'"
  "`$env:CLAWOSS_DASHBOARD_AUTO_GITHUB_SYNC='$autoGithubSyncEnv'"
  "Set-Location '$dashboardDir'"
  "& '$npxCmd' next start --hostname $dashboardHost --port $dashboardPort"
) -join "; "

$dashboardStart = @{
  FilePath = $powershellExe
  ArgumentList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $dashboardCommand)
  WorkingDirectory = $dashboardDir
  RedirectStandardOutput = $dashboardStdout
  RedirectStandardError = $dashboardStderr
  WindowStyle = "Hidden"
}
Start-Process @dashboardStart | Out-Null

Start-Sleep -Seconds 8

$cloudflaredStart = @{
  FilePath = $cloudflaredExe
  ArgumentList = @(
    "tunnel",
    "--loglevel", "info",
    "--logfile", $cloudflaredLog,
    "--pidfile", $cloudflaredPid,
    "run",
    "--token", [string]$config.tunnelToken,
    "--url", "http://127.0.0.1:$dashboardPort"
  )
  WorkingDirectory = $repoRoot
  WindowStyle = "Hidden"
}
Start-Process @cloudflaredStart | Out-Null

Write-Output "Dashboard directory: $dashboardDir"
Write-Output "Dashboard port: $dashboardPort"
Write-Output "Cloudflared log: $cloudflaredLog"
Write-Output "Cloudflared pid file: $cloudflaredPid"

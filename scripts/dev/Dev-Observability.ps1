[CmdletBinding()]
param(
  [ValidateSet('start','stop','restart','status')]
  [string]$Action = 'start',
  [switch]$NoBrowser,
  [switch]$Pull
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $PSCommandPath
$RepoRoot   = Split-Path -Parent (Split-Path -Parent $ScriptRoot)
$composeFile = Join-Path $ScriptRoot 'observability-compose.yml'
if (-not (Test-Path -LiteralPath $composeFile)) {
  throw "Expected compose file '$composeFile'."
}
$composeFile = (Resolve-Path $composeFile).Path

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker CLI is required but was not found in PATH.'
}

$env:COMPOSE_PROJECT_NAME = 'blackcat_obs'

function Invoke-Compose {
  param([string[]]$ComposeArgs)
  $args = @('compose','-f',$composeFile) + $ComposeArgs
  Write-Host ("docker {0}" -f ($args -join ' ')) -ForegroundColor Cyan
  & docker @args
}

switch ($Action) {
  'start' {
    if ($Pull -or $env:BLACKCAT_OBS_PULL -eq '1') {
      Invoke-Compose @('pull')
    }
    Invoke-Compose @('up','-d','--remove-orphans')
    Write-Host 'Observability stack is running:' -ForegroundColor Green
    Write-Host '  Grafana:     http://localhost:3000  (admin / devpass)'
    Write-Host '  Prometheus: http://localhost:9090'
    Write-Host '  Loki:       http://localhost:3100'
    if (-not $NoBrowser) {
      try {
        Start-Process 'http://localhost:3000' | Out-Null
      } catch {
        Write-Host "Open Grafana manually at http://localhost:3000" -ForegroundColor Yellow
      }
    }
  }
  'stop' {
    Invoke-Compose @('down')
  }
  'restart' {
    Invoke-Compose @('down')
    Invoke-Compose @('up','-d','--remove-orphans')
  }
  'status' {
    Invoke-Compose @('ps')
  }
  default {
    throw "Unsupported action '$Action'"
  }
}

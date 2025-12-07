param(
    [switch]$BuildImage
)

$ErrorActionPreference = "Stop"
$image = "blackcat/act-runner"

Write-Host "Stopping local DB containers on 3306/3307/5432 (if any)..." -ForegroundColor Cyan
$containers = & docker ps --format "{{.ID}} {{.Ports}}"
foreach ($line in $containers) {
    if ($line -match "3306|3307|5432") {
        $id = ($line -split " ")[0]
        if ($id) { & docker stop $id | Out-Null }
    }
}

if ($BuildImage -or -not ((& docker image ls --format "{{.Repository}}:{{.Tag}}") | Where-Object { $_ -eq $image })) {
    Write-Host "Building runner image $image ..." -ForegroundColor Cyan
    & docker build -t $image -f docker/act-runner.Dockerfile .
}

$actArgs = $args -join " "
$logDir  = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("act-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log")

Write-Host "Launching act inside $image (logging to $logFile) ..." -ForegroundColor Cyan
$innerCmd = "set -e; act -P ubuntu-latest=catthehacker/ubuntu:act-latest $actArgs"
$dockerCmd = "docker.exe"
$runArgs = @(
  "--rm",
  "--entrypoint","/bin/bash",
  "-w","/github/workspace",
  "-v","${PWD}:/github/workspace",
  "-v","//var/run/docker.sock:/var/run/docker.sock",
  $image,
  "-lc",$innerCmd
)
$output = & $dockerCmd $runArgs 2>&1
$output | Tee-Object -FilePath $logFile

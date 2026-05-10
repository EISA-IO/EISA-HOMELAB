#Requires -Version 5.1
<#
.SYNOPSIS
  Cleanly stops the EISA Homelab Ultimate stack.

.PARAMETER Volumes
  Also remove docker volumes (DESTRUCTIVE — wipes ollama models, open-webui
  data, jellyfin cache, filebrowser DB, etc.). Bind-mounted persistent-storage
  on disk is NOT touched.

.PARAMETER Prune
  Run `docker system prune -f` after shutdown to reclaim disk space from
  dangling images / build cache. Leaves named volumes alone (use -Volumes
  for that).
#>

[CmdletBinding()]
param(
    [switch]$Volumes,
    [switch]$Prune
)

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

function Write-Step  { param([string]$T) Write-Host ''; Write-Host ">>> $T" -ForegroundColor Yellow }
function Write-Ok    { param([string]$T) Write-Host "    [OK] $T" -ForegroundColor Green }
function Write-Err   { param([string]$T) Write-Host "    [X]  $T" -ForegroundColor Red }

function Ask-YesNo {
    param([string]$Prompt, [bool]$DefaultYes = $false)
    $def = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $a = (Read-Host "$Prompt [$def]").Trim().ToLower()
        if ([string]::IsNullOrEmpty($a)) { return $DefaultYes }
        if ($a -in @('y','yes')) { return $true }
        if ($a -in @('n','no'))  { return $false }
    }
}

Write-Step 'Stopping EISA Homelab Ultimate stack'

# If neither flag was passed, ask once whether to nuke volumes.
if (-not $Volumes -and -not $Prune) {
    $Volumes = Ask-YesNo 'Also remove docker volumes? (DESTRUCTIVE — wipes container DBs/caches)' $false
    $Prune   = Ask-YesNo 'Run `docker system prune -f` afterwards to reclaim disk?' $false
}

$args = @('compose','down')
if ($Volumes) { $args += '--volumes' }
$args += '--remove-orphans'

& docker @args
if ($LASTEXITCODE -ne 0) {
    Write-Err 'docker compose down failed.'
    exit $LASTEXITCODE
}
Write-Ok 'Stack stopped.'

if ($Prune) {
    Write-Step 'Pruning dangling images / build cache'
    & docker system prune -f
    Write-Ok 'Prune done.'
}

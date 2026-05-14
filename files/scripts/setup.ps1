#Requires -Version 5.1
<#
.SYNOPSIS
  EISA Homelab Ultimate — beginner-friendly first-run wizard.

.DESCRIPTION
  On a fresh checkout, walks the user through:
    1. Picking a stack (AI / Media+Productivity / Ultimate)
    2. Choosing local-only vs Cloudflare tunnel access
    3. Pointing at their media folders by friendly name
    4. Generating strong secrets silently
    5. Starting the right docker compose profiles
    6. Pulling a first LLM if the AI stack is selected and no models exist
  On subsequent runs, lets the user just start their existing stack.

.PARAMETER Reconfigure
  Force the first-run wizard even if .env / .wizard-state.json are populated.

.PARAMETER NoStart
  Run the wizard but skip `docker compose up`.
#>

[CmdletBinding()]
param(
    # First-run mode (no flag): run the full wizard.
    [switch]$Reconfigure,   # force re-asking every value even if .env has it
    [switch]$NoStart,       # render configs but don't `docker compose up`
    [switch]$StartOnly      # skip wizard entirely; just bring the existing stack up
)

# ---------------------------------------------------------------------------
# Locate project root (one level up from this script).
# ---------------------------------------------------------------------------
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

$EnvFile         = Join-Path $ProjectRoot '.env'
$EnvExample      = Join-Path $ProjectRoot '.env.example'
$StateFile       = Join-Path $ProjectRoot '.wizard-state.json'
$RecommendedFile = Join-Path $ProjectRoot 'recommended_models.txt'

# Make the console UTF-8 so the ASCII-art logo renders.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new() } catch {}

# Maximize the host console window so the wizard has room to breathe.
# Win32 ShowWindow(SW_MAXIMIZE = 3) on the current console window handle.
# No-op on macOS/Linux; silently ignored if the host doesn't allow it
# (some Windows Terminal configs treat the tab as a pseudo-console).
function Maximize-Console {
    $isWin = $true
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        if (-not $IsWindows) { $isWin = $false }
    }
    if (-not $isWin) { return }
    try {
        if (-not ('EisaConsoleHelper' -as [type])) {
            Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EisaConsoleHelper {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]   public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
        }
        $hwnd = [EisaConsoleHelper]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            [void][EisaConsoleHelper]::ShowWindow($hwnd, 3)  # SW_MAXIMIZE
        }
    } catch {}
}
Maximize-Console

# ---------------------------------------------------------------------------
# Output helpers — green/minimal house style.
# ---------------------------------------------------------------------------
function G   { param([string]$T = '') Write-Host $T -ForegroundColor Green }
function Dim { param([string]$T = '') Write-Host $T -ForegroundColor DarkGreen }
function Err { param([string]$T) Write-Host "  ! $T" -ForegroundColor Red }
function Ok  { param([string]$T) Write-Host "  $([char]0x2713) $T" -ForegroundColor Green }

function Show-Logo {
    # NOTE: deliberately no Clear-Host here — when invoked from a .bat
    # launcher we want the bat's pre-amble (steps 1..4) to stay visible
    # above the logo so the user has a full audit trail of what ran.
    G ''
    G '   ███████╗██╗███████╗ █████╗'
    G '   ██╔════╝██║██╔════╝██╔══██╗'
    G '   █████╗  ██║███████╗███████║'
    G '   ██╔══╝  ██║╚════██║██╔══██║'
    G '   ███████╗██║███████║██║  ██║'
    G '   ╚══════╝╚═╝╚══════╝╚═╝  ╚═╝'
    G '   H O M E L A B    U L T I M A T E'
    G ''
    G '   The ULTIMATE private, no-tracking homelab stack.'
    Dim '   100% local-first  |  zero telemetry  |  your data, your machine'
    G ''
}

function Step {
    param([string]$Title, [string]$Hint = '')
    G ''
    G "  $Title"
    if ($Hint) { Dim "  $Hint" }
    G ''
}

# ---------------------------------------------------------------------------
# Prompts.
# ---------------------------------------------------------------------------
function Ask {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$Default = '',
        [switch]$Secret,
        [switch]$AllowEmpty
    )
    while ($true) {
        $hint = if ($Default) { " [$Default]" } else { '' }
        Write-Host "  $Prompt$hint " -NoNewline -ForegroundColor Green
        if ($Secret) {
            $sec  = Read-Host -AsSecureString
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            $val  = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        } else {
            $val = Read-Host
        }
        if ([string]::IsNullOrWhiteSpace($val)) { $val = $Default }
        if ([string]::IsNullOrWhiteSpace($val) -and -not $AllowEmpty) {
            Err "this can't be blank"
            continue
        }
        return $val
    }
}

# Open a URL in the user's default browser (best effort, no-op on failure).
function Open-Browser {
    param([Parameter(Mandatory)][string]$Url)
    try {
        switch ($script:OS) {
            'Windows' { Start-Process $Url | Out-Null }
            'Mac'     { & open $Url 2>$null | Out-Null }
            'Linux'   { & xdg-open $Url 2>$null | Out-Null }
        }
    } catch {}
}

function Ask-YesNo {
    param([string]$Prompt, [bool]$DefaultYes = $true)
    $def = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    while ($true) {
        Write-Host "  $Prompt [$def] " -NoNewline -ForegroundColor Green
        $a = (Read-Host).Trim().ToLower()
        if ([string]::IsNullOrEmpty($a)) { return $DefaultYes }
        if ($a -in @('y','yes')) { return $true }
        if ($a -in @('n','no'))  { return $false }
        Err 'answer y or n'
    }
}

function Ask-Choice {
    param([Parameter(Mandatory)][object[]]$Options)
    while ($true) {
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $opt = $Options[$i]
            G ("    [{0}] {1}" -f ($i + 1), $opt.Label)
            if ($opt.PSObject.Properties['Hint'] -and $opt.Hint) {
                $lines = if ($opt.Hint -is [array]) { $opt.Hint } else { @($opt.Hint) }
                foreach ($ln in $lines) { Dim ("        $ln") }
            }
        }
        G ''
        Write-Host '  > ' -NoNewline -ForegroundColor Green
        $pick = Read-Host
        $n = 0
        if ([int]::TryParse($pick, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            return $n
        }
        Err 'pick a number from the list'
    }
}

# Multi-pick service picker for the CUSTOM stack option. Each entry has a
# friendly label + the underlying docker compose service name(s) it represents
# (so 'Immich' expands to its 4 sidecars). Returns the flat list of service
# names to pass to `docker compose up`.
function Invoke-CustomServicePicker {
    $entries = @(
        # AI
        [pscustomobject]@{ Label='ollama               (local LLMs - the brain)';                  Services=@('ollama') }
        [pscustomobject]@{ Label='open-webui           (ChatGPT-style chat interface for the AI)'; Services=@('open-webui') }
        [pscustomobject]@{ Label='searxng              (private metasearch engine)';               Services=@('searxng') }
        [pscustomobject]@{ Label='local-deep-research  (AI research assistant)';                   Services=@('local-deep-research') }
        [pscustomobject]@{ Label='vane                 (Perplexity-style answer engine)';          Services=@('vane') }
        [pscustomobject]@{ Label='hermes               (NousResearch self-improving agent + workspace UI)'; Services=@('hermes-agent','hermes-workspace') }
        [pscustomobject]@{ Label='n8n                  (workflow automation; bundles postgres + qdrant)'; Services=@('n8n','n8n-postgres','qdrant') }
        # MEDIA
        [pscustomobject]@{ Label='jellyfin             (movie + TV streaming)';                    Services=@('jellyfin') }
        [pscustomobject]@{ Label='navidrome            (music streaming)';                         Services=@('navidrome') }
        [pscustomobject]@{ Label='immich               (photo + video library; bundles DB/Redis/ML)'; Services=@('immich-server','immich-machine-learning','immich-redis','immich-postgres') }
        # PRODUCTIVITY
        [pscustomobject]@{ Label='filebrowser          (web file manager)';                        Services=@('filebrowser') }
        [pscustomobject]@{ Label='omni-tools           (grab-bag of web utilities)';               Services=@('omni-tools') }
        [pscustomobject]@{ Label='tor-browser          (Tor Browser in a browser tab)';            Services=@('tor-browser') }
    )

    G ''
    G  '  CUSTOM stack - pick the apps you want.'
    Dim '  Type comma- or space-separated numbers (e.g. "1,3,7" or "1 3 7"),'
    Dim '  "all" to pick everything, or "ai" / "media" / "prod" for shortcut bundles.'
    G ''
    for ($i = 0; $i -lt $entries.Count; $i++) {
        G ("    [{0}] {1}" -f ($i + 1), $entries[$i].Label)
    }
    G ''
    Write-Host '  > ' -NoNewline -ForegroundColor Green
    $raw = Read-Host
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

    $picked = @()
    $lower  = $raw.Trim().ToLower()
    if ($lower -eq 'all') {
        $picked = 1..$entries.Count
    } elseif ($lower -eq 'ai') {
        $picked = 1..7
    } elseif ($lower -eq 'media') {
        $picked = 8..10
    } elseif ($lower -in @('prod','productivity')) {
        $picked = 11..13
    } else {
        # Split on commas, spaces, or both; keep numeric tokens only.
        $tokens = $raw -split '[,\s]+' | Where-Object { $_ -match '^[0-9]+$' }
        foreach ($t in $tokens) {
            $n = [int]$t
            if ($n -ge 1 -and $n -le $entries.Count -and ($picked -notcontains $n)) {
                $picked += $n
            }
        }
    }

    $services = @()
    foreach ($p in $picked) {
        $services += $entries[$p - 1].Services
    }
    return ($services | Select-Object -Unique)
}

# ---------------------------------------------------------------------------
# Docker preflight — detect OS, status, and auto-install if missing.
# ---------------------------------------------------------------------------
function Get-OS {
    # $IsWindows / $IsMacOS / $IsLinux only exist on PowerShell 6+.
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        if ($IsWindows) { return 'Windows' }
        if ($IsMacOS)   { return 'Mac' }
        if ($IsLinux)   { return 'Linux' }
    }
    # PowerShell 5.1 only runs on Windows.
    return 'Windows'
}

function Get-DockerStatus {
    # 0 = CLI present and engine reachable
    # 1 = CLI present but engine not running
    # 2 = CLI not installed
    try {
        $null = & docker --version 2>&1
        if ($LASTEXITCODE -ne 0) { return 2 }
    } catch { return 2 }
    try {
        $null = & docker info --format '{{.ServerVersion}}' 2>&1
        if ($LASTEXITCODE -ne 0) { return 1 }
    } catch { return 1 }
    return 0
}

function Wait-DockerEngine {
    param([int]$TimeoutSeconds = 300)
    Dim "  Waiting for the Docker engine to come up (up to $TimeoutSeconds s)..."
    $start = Get-Date
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $null = & docker info --format '{{.ServerVersion}}' 2>&1
            if ($LASTEXITCODE -eq 0) {
                Ok 'Docker engine is up.'
                return $true
            }
        } catch {}
        Start-Sleep -Seconds 2
    }
    return $false
}

function Start-DockerDesktop {
    param([string]$OS)
    if ($OS -eq 'Windows') {
        $candidates = @(
            (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\Docker Desktop.exe')
        )
        foreach ($c in $candidates) {
            if ($c -and (Test-Path $c)) {
                Start-Process -FilePath $c | Out-Null
                return
            }
        }
    } elseif ($OS -eq 'Mac') {
        & open -a 'Docker' 2>$null
    }
}

function Install-DockerWindows {
    # Try winget first.
    $wingetOk = $false
    try {
        $null = & winget --version 2>&1
        if ($LASTEXITCODE -eq 0) { $wingetOk = $true }
    } catch {}

    if ($wingetOk) {
        Dim '  Installing Docker Desktop via winget (a UAC prompt will appear)...'
        Start-Process -Verb RunAs -Wait -FilePath 'winget' -ArgumentList @(
            'install','-e','--id','Docker.DockerDesktop',
            '--silent','--accept-source-agreements','--accept-package-agreements'
        ) -ErrorAction SilentlyContinue
        # winget via Start-Process doesn't propagate $LASTEXITCODE; verify by re-checking docker.
        try { $null = & docker --version 2>&1 } catch {}
        if ($LASTEXITCODE -eq 0) {
            Ok 'Docker Desktop installed via winget.'
            return $true
        }
        Dim '  winget path did not complete cleanly. Falling back to MSI download...'
    }

    # MSI / EXE fallback.
    $url       = 'https://desktop.docker.com/win/main/amd64/Docker Desktop Installer.exe'
    $installer = Join-Path $env:TEMP 'DockerDesktopInstaller.exe'
    Dim '  Downloading Docker Desktop installer (~600 MB)...'
    try {
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    } catch {
        Err "Download failed: $($_.Exception.Message)"
        return $false
    }
    Dim '  Running Docker Desktop installer (a UAC prompt will appear)...'
    Start-Process -Verb RunAs -Wait -FilePath $installer -ArgumentList @(
        'install','--quiet','--accept-license'
    ) -ErrorAction SilentlyContinue
    Remove-Item $installer -ErrorAction SilentlyContinue
    return $true
}

function Install-DockerMac {
    # Try Homebrew first.
    $brewOk = $false
    try {
        $null = & brew --version 2>&1
        if ($LASTEXITCODE -eq 0) { $brewOk = $true }
    } catch {}

    if ($brewOk) {
        Dim '  Installing Docker Desktop via Homebrew...'
        & brew install --cask docker
        if ($LASTEXITCODE -eq 0) {
            Ok 'Docker Desktop installed via Homebrew.'
            return $true
        }
        Dim '  brew install failed. Falling back to DMG download...'
    }

    # DMG fallback.
    $arch   = ((& uname -m) | Out-String).Trim()
    $dmgUrl = if ($arch -eq 'arm64') {
        'https://desktop.docker.com/mac/main/arm64/Docker.dmg'
    } else {
        'https://desktop.docker.com/mac/main/amd64/Docker.dmg'
    }
    $dmg = '/tmp/Docker.dmg'
    Dim "  Downloading Docker.dmg for $arch..."
    try {
        Invoke-WebRequest -Uri $dmgUrl -OutFile $dmg -UseBasicParsing
    } catch {
        Err "Download failed: $($_.Exception.Message)"
        return $false
    }
    Dim '  Mounting DMG...'
    & hdiutil attach $dmg -nobrowse -quiet
    Dim '  Copying Docker.app into /Applications (you may be prompted for your password)...'
    & sudo cp -R '/Volumes/Docker/Docker.app' '/Applications/'
    & hdiutil detach '/Volumes/Docker' -quiet
    Remove-Item $dmg -ErrorAction SilentlyContinue
    return $true
}

function Ensure-Docker {
    param([string]$OS)

    $status = Get-DockerStatus

    if ($status -eq 0) {
        # All good.
        return
    }

    if ($status -eq 1) {
        # CLI is there, engine isn't. Try to start Docker Desktop and wait.
        Dim '  Docker is installed but the engine is not running. Starting Docker Desktop...'
        Start-DockerDesktop -OS $OS
        if (Wait-DockerEngine -TimeoutSeconds 180) { return }
        Err 'Docker engine did not come up. Launch Docker Desktop manually and re-run.'
        exit 1
    }

    # status -eq 2 — CLI missing. Offer to install.
    Step 'Docker Desktop is not installed' "We can download and install it for you now. Expect a UAC / password prompt once."
    if (-not (Ask-YesNo 'Install Docker Desktop now?' $true)) {
        Err 'Docker Desktop is required. Install it manually and re-run.'
        Dim '  https://www.docker.com/products/docker-desktop/'
        exit 1
    }

    $installed = switch ($OS) {
        'Windows' { Install-DockerWindows }
        'Mac'     { Install-DockerMac }
        default {
            Err "Sorry, auto-install isn't wired up for $OS. Install Docker manually and re-run."
            Dim '  https://www.docker.com/products/docker-desktop/'
            exit 1
        }
    }

    if (-not $installed) {
        Err 'Auto-install did not complete. Install Docker Desktop manually and re-run.'
        Dim '  https://www.docker.com/products/docker-desktop/'
        exit 1
    }

    Ok 'Docker Desktop installed. Launching it...'
    Start-DockerDesktop -OS $OS

    if (-not (Wait-DockerEngine -TimeoutSeconds 300)) {
        Err 'Docker engine did not come up within 5 minutes.'
        Dim "  On Windows this usually means WSL2 was set up and Windows needs a sign-out or reboot."
        Dim '  Sign out / reboot, launch Docker Desktop manually, then re-run.'
        exit 1
    }
}

# ---------------------------------------------------------------------------
# .env IO + secret generation (unchanged shapes from prior wizard).
# ---------------------------------------------------------------------------
function Read-EnvFile {
    param([string]$Path)
    $map = [ordered]@{}
    if (-not (Test-Path $Path)) { return $map }
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            $map[$Matches[1]] = $Matches[2]
        }
    }
    return $map
}

function Write-EnvFile {
    param([string]$Path, $Map)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Generated by setup.ps1 — open the HOMELAB-MANAGER launcher and pick [1] First-Run Setup to change values.')
    [void]$sb.AppendLine('# Sensitive: never commit this file (it is gitignored).')
    foreach ($k in $Map.Keys) {
        [void]$sb.AppendLine("$k=$($Map[$k])")
    }
    Set-Content -Path $Path -Value $sb.ToString() -Encoding ASCII
}

function New-HexSecret {
    param([int]$Bytes = 32)
    $b = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    -join ($b | ForEach-Object { $_.ToString('x2') })
}

function New-Base64Secret {
    param([int]$Bytes = 32)
    $b = New-Object byte[] $Bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    [Convert]::ToBase64String($b)
}

function Test-Placeholder {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return $Value -match '^__.*__$' -or $Value -match 'CHANGE_ME' -or $Value -match 'GENERATE_'
}

# Normalise Windows paths to docker-compose-friendly form.
function Format-Path {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $p = $Path.Trim().Trim('"').Trim("'")
    return $p -replace '\\', '/'
}

# ---------------------------------------------------------------------------
# State file (so subsequent runs can "just start").
# ---------------------------------------------------------------------------
function Read-State {
    if (-not (Test-Path $StateFile)) { return $null }
    try { return Get-Content $StateFile -Raw | ConvertFrom-Json } catch { return $null }
}

function Write-State {
    param($State)
    $State | ConvertTo-Json -Depth 5 | Set-Content $StateFile -Encoding ASCII
}

# ---------------------------------------------------------------------------
# The first-run wizard.
# ---------------------------------------------------------------------------
function Invoke-Wizard {
    # Bootstrap .env from .env.example if missing.
    if (-not (Test-Path $EnvFile)) {
        Copy-Item $EnvExample $EnvFile
    }
    $envMap     = Read-EnvFile $EnvFile
    $exampleMap = Read-EnvFile $EnvExample
    foreach ($k in $exampleMap.Keys) {
        if (-not $envMap.Contains($k)) { $envMap[$k] = $exampleMap[$k] }
    }

    # ---- Step 1: stack ----------------------------------------------------
    Step 'Step 1 — Pick what to install' 'Each option starts a different set of containers. You can re-run the first-run launcher to change later.'
    Dim '  Always installed (the core):'
    Dim '    Heimdall   start page'
    Dim '    Caddy      reverse proxy'
    Dim '    Authelia   SSO gateway'
    Dim '    Portainer  Docker UI'
    G ''
    $stackPick = Ask-Choice @(
        [pscustomobject]@{
            Label = 'AI'
            Hint  = @(
                'ollama              local LLMs'
                'open-webui          chat interface'
                'searxng             private search'
                'local-deep-research AI research'
                'vane                answer engine'
                'hermes-agent        self-improving agent'
                'hermes-workspace    web UI for hermes-agent'
                'n8n + postgres      workflow automation'
                'qdrant              vector database'
            )
        }
        [pscustomobject]@{
            Label = 'MEDIA (streaming only)'
            Hint  = @(
                'jellyfin            movie + TV streaming'
                'navidrome           music streaming'
                'immich              photo + video library'
            )
        }
        [pscustomobject]@{
            Label = 'PRODUCTIVITY (utilities only)'
            Hint  = @(
                'filebrowser         file manager'
                'omni-tools          web utilities'
                'tor-browser         anonymous browser'
            )
        }
        [pscustomobject]@{
            Label = 'ULTIMATE (everything - recommended)'
            Hint  = @(
                'Everything from AI + MEDIA + PRODUCTIVITY.'
            )
        }
        [pscustomobject]@{
            Label = 'CUSTOM (pick individual apps)'
            Hint  = @(
                'Show a checklist of every app and let me choose exactly'
                'which ones to start.'
            )
        }
    )

    $customServices = @()
    $profiles       = @()
    $stack          = switch ($stackPick) {
        1 { 'ai' }
        2 { 'media' }
        3 { 'productivity' }
        4 { 'ultimate' }
        5 { 'custom' }
    }
    switch ($stack) {
        'ai'           { $profiles = @('ai') }
        'media'        { $profiles = @('media-stream') }
        'productivity' { $profiles = @('productivity') }
        'ultimate'     { $profiles = @('ai','media') }
        'custom'       {
            $customServices = Invoke-CustomServicePicker
            if (-not $customServices -or $customServices.Count -eq 0) {
                Dim '  No apps picked - defaulting to ULTIMATE.'
                $stack    = 'ultimate'
                $profiles = @('ai','media')
                $customServices = @()
            }
        }
    }

    # Compatibility flags surfaced in the summary / state blob.
    $hasAi    = ($profiles -contains 'ai') -or `
                ($customServices | Where-Object { $_ -in 'ollama','open-webui','searxng','local-deep-research','vane','hermes-agent','hermes-workspace','n8n','n8n-postgres','qdrant' }).Count -gt 0
    $hasMedia = ($profiles -contains 'media') -or ($profiles -contains 'media-stream') -or ($profiles -contains 'productivity') -or `
                ($customServices | Where-Object { $_ -in 'jellyfin','navidrome','immich-server','filebrowser','omni-tools','tor-browser' }).Count -gt 0
    Ok "Stack: $($stack.ToUpper())"

    # ---- Step 2: access mode ---------------------------------------------
    Step 'Step 2 — Hosting: local or online?' 'This decides whether your stack lives only on your LAN, or is reachable from anywhere on the internet through your own domain.'
    $accessPick = Ask-Choice @(
        [pscustomobject]@{
            Label = 'LOCAL HOSTING (recommended — safe default)'
            Hint  = @(
                'Apps reachable at http://localhost:PORT on this machine'
                'and on your LAN. Nothing exposed to the public internet.'
                'No domain, no Cloudflare account, no SSO required.'
            )
        }
        [pscustomobject]@{
            Label = 'ONLINE HOSTING via Cloudflare tunnel'
            Hint  = @(
                'Apps reachable from anywhere at chat.yourdomain.com,'
                'movie.yourdomain.com, etc. Gated by Authelia SSO.'
                'Requires: a domain on Cloudflare + a free tunnel'
                'token from https://dash.cloudflare.com/.'
            )
        }
    )
    $useTunnel = ($accessPick -eq 2)

    if ($useTunnel) {
        Step 'Step 2a — Cloudflare tunnel setup (walkthrough)' 'This wizard installs cloudflared automatically. You only need to grab a token from Cloudflare and tell us your domain.'
        G  '  PART A - Get your tunnel token (you do this now in your browser):'
        G  ''
        Dim '    1) Open  https://dash.cloudflare.com/'
        Dim '    2) Left sidebar:  Networks  ->  Tunnels'
        Dim '    3) Click  "Create a tunnel"'
        Dim '    4) Connector type:  Cloudflared'
        Dim '    5) Name your tunnel  (anything, e.g. "homelab")'
        Dim '    6) Click  "Save tunnel"'
        Dim '    7) The next page shows install commands - IGNORE THEM.'
        Dim '       We run cloudflared in Docker; we only need the token.'
        Dim '    8) Find the long string after `--token` in the install command'
        Dim '       (~150 chars, starts with "ey..."). That is your token.'
        Dim '    9) Copy ONLY the token (not the whole `cloudflared service`'
        Dim '       command), then paste it below.'
        G  ''
        Dim '  PART B comes after the stack is up - you will get instructions'
        Dim '  for adding Public Hostnames in Cloudflare so your subdomains'
        Dim '  actually route to the stack.'
        G  ''
        if (Ask-YesNo '  Open https://dash.cloudflare.com/ in your browser now?' $true) {
            Open-Browser 'https://dash.cloudflare.com/'
        }
        G  ''
        $envMap['DOMAIN']                  = Ask 'Your domain (e.g. example.com)' $envMap['DOMAIN']
        $envMap['CLOUDFLARE_TUNNEL_TOKEN'] = Ask 'Cloudflare tunnel token' $envMap['CLOUDFLARE_TUNNEL_TOKEN'] -Secret
    } else {
        $envMap['DOMAIN']                  = ''
        $envMap['CLOUDFLARE_TUNNEL_TOKEN'] = ''
    }
    Ok ("Access: " + ($(if ($useTunnel) { "ONLINE ($($envMap['DOMAIN']))" } else { 'LOCAL only' })))

    # ---- Step 2b: Heimdall start-page tile URLs --------------------------
    # Heimdall ships a curated set of dashboard tiles whose URLs all point at
    # the maintainer's domain. We give the user one chance, here, to put
    # their own domain in — or leave blank for localhost-only mode.
    # The actual SQL rewrite runs later in Ensure-HeimdallTiles and is
    # idempotent: it only fires while the placeholder URLs are still in the
    # DB, so re-runs and user customizations are safe.
    Step 'Step 2b — Heimdall start-page tiles' 'Tell us where the dashboard tiles should point. We rewrite them only once, the first time we see the placeholder URLs.'
    G  '  Type the domain you want your dashboard tiles to use, or leave blank'
    G  '  for local-only mode. In local mode tiles use http://<sub>.localhost'
    G  '  URLs which auto-resolve to 127.0.0.1 in every modern browser — Caddy'
    G  '  proxies them to the right container on port 80.'
    G  ''
    Dim '    With "example.com":  https://chat.example.com, https://movie.example.com, ...'
    Dim '    Blank (local-only):  http://chat.localhost, http://photos.localhost, http://movie.localhost ...'
    G  ''
    $tileDefault = if (-not (Test-Placeholder $envMap['HEIMDALL_TILE_DOMAIN'])) {
        $envMap['HEIMDALL_TILE_DOMAIN']
    } elseif ($envMap['DOMAIN']) {
        $envMap['DOMAIN']
    } else { '' }
    $envMap['HEIMDALL_TILE_DOMAIN'] = Ask 'Domain for Heimdall tiles (blank = *.localhost)' $tileDefault -AllowEmpty
    if ($envMap['HEIMDALL_TILE_DOMAIN']) {
        Ok ("Heimdall tiles  ->  https://*." + $envMap['HEIMDALL_TILE_DOMAIN'])
    } else {
        Ok 'Heimdall tiles  ->  http://*.localhost (local-only, via Caddy)'
    }

    # ---- Step 3: persistent storage --------------------------------------
    if (Test-Placeholder $envMap['PERSISTENT_STORAGE']) {
        $envMap['PERSISTENT_STORAGE'] = './persistent-storage'
    }

    # ---- Step 4: media folders (only if media stack) ---------------------
    if ($hasMedia) {
        if ($script:OS -eq 'Mac') {
            $pathHint = 'Type the full path to each folder. Examples: ~/Movies, /Volumes/Media/Movies'
            # If the defaults still look Windows-y, swap to sensible Mac defaults.
            $homePath = $HOME
            foreach ($k in @('MOVIES_PATH','TV_SHOWS_PATH','MUSIC_PATH','DOWNLOADS_PATH','PHOTOS_PATH')) {
                if (-not $envMap.Contains($k) -or $envMap[$k] -match '^[A-Za-z]:') {
                    $envMap[$k] = switch ($k) {
                        'MOVIES_PATH'    { "$homePath/Movies" }
                        'TV_SHOWS_PATH'  { "$homePath/TV-Shows" }
                        'MUSIC_PATH'     { "$homePath/Music" }
                        'DOWNLOADS_PATH' { "$homePath/Downloads" }
                        'PHOTOS_PATH'    { "$homePath/Photos" }
                    }
                }
            }
        } else {
            $pathHint = 'Type the full path to each folder. Examples: F:\Movies, D:\TV-Shows, F:/Music'
        }
        if (-not $envMap.Contains('PHOTOS_PATH') -or [string]::IsNullOrWhiteSpace($envMap['PHOTOS_PATH'])) {
            $envMap['PHOTOS_PATH'] = 'F:/Photos'
        }
        Step 'Step 3 — Your media folders' $pathHint
        $envMap['MOVIES_PATH']    = Format-Path (Ask 'MOVIES FOLDER LOCATION'    $envMap['MOVIES_PATH'])
        $envMap['TV_SHOWS_PATH']  = Format-Path (Ask 'TV SHOWS FOLDER LOCATION'  $envMap['TV_SHOWS_PATH'])
        $envMap['MUSIC_PATH']     = Format-Path (Ask 'MUSIC FOLDER LOCATION'     $envMap['MUSIC_PATH'])
        $envMap['DOWNLOADS_PATH'] = Format-Path (Ask 'DOWNLOADS FOLDER LOCATION' $envMap['DOWNLOADS_PATH'])
        $envMap['PHOTOS_PATH']    = Format-Path (Ask 'PHOTOS FOLDER LOCATION (Immich library)' $envMap['PHOTOS_PATH'])
        Ok 'Media folders saved.'
    }

    # ---- Step 3b: GPU acceleration for Ollama (only if AI in stack) ------
    $gpuMode = 'cpu'
    if ($hasAi) {
        $detected = Get-OllamaGpuMode -OS $script:OS
        Step 'Step 3b — GPU acceleration for Ollama' "We auto-detected your GPU as: $($detected.ToUpper()). You can override below if needed."

        # On macOS we offer a fifth option: run Ollama NATIVELY on the host
        # (Homebrew or ollama.app) so it uses Metal. Docker on Mac can't
        # pass Metal through to containers, so this is the only way to get
        # real GPU acceleration on Apple Silicon.
        if ($script:OS -eq 'Mac') {
            $gpuPick = Ask-Choice @(
                [pscustomobject]@{
                    Label = 'NATIVE Ollama on macOS (Metal-accelerated)  -- recommended for Apple Silicon'
                    Hint  = @(
                        'Skips the in-container ollama. Open WebUI, Local Deep Research,'
                        'and Vane will point at http://host.docker.internal:11434 so'
                        'Mac-native Ollama (using Metal) serves them. Massive speedup'
                        'on M1/M2/M3 vs containerised CPU.'
                        '  Setup: brew install ollama && brew services start ollama'
                        '  Verify: curl http://localhost:11434/api/tags'
                    )
                }
                [pscustomobject]@{
                    Label = 'CPU only (containerised ollama)'
                    Hint  = @(
                        'Runs ollama inside Docker on Mac. Works without any host'
                        'install but is much slower since the container cannot reach Metal.'
                    )
                }
            )
            $gpuMode = switch ($gpuPick) {
                1 { 'native' }
                2 { 'cpu' }
            }
        } else {
            $gpuPick = Ask-Choice @(
                [pscustomobject]@{
                    Label = "Use auto-detected: $($detected.ToUpper())"
                    Hint  = @(
                        'Recommended. Trust the detection unless you know better.'
                    )
                }
                [pscustomobject]@{
                    Label = 'NVIDIA (CUDA)'
                    Hint  = @(
                        'Requires NVIDIA driver + Docker Desktop "Enable GPU support",'
                        'or on Linux: nvidia-container-toolkit installed.'
                    )
                }
                [pscustomobject]@{
                    Label = 'AMD (ROCm) - Linux only'
                    Hint  = @(
                        'Requires ROCm-compatible AMD GPU + ROCm drivers on a Linux host.'
                        'Docker Desktop on Windows does NOT support AMD passthrough.'
                    )
                }
                [pscustomobject]@{
                    Label = 'CPU only'
                    Hint  = @(
                        'Works on every machine but slower. Use this if your GPU'
                        'is unsupported or you want predictable resource use.'
                    )
                }
            )
            $gpuMode = switch ($gpuPick) {
                1 { $detected }
                2 { 'nvidia' }
                3 { 'amd' }
                4 { 'cpu' }
            }
        }
        Ok "GPU mode: $($gpuMode.ToUpper())"
    }

    # ---- Step 5: passwords + secrets -------------------------------------
    Step 'Step 4 — Secrets' 'Generating strong random keys for databases, n8n, and SSO. Nothing for you to type.'
    $genSpecs = @(
        @{ Key='POSTGRES_PASSWORD';              Bytes=24; Mode='hex' }
        @{ Key='N8N_ENCRYPTION_KEY';             Bytes=32; Mode='hex' }
        @{ Key='N8N_USER_MANAGEMENT_JWT_SECRET'; Bytes=32; Mode='hex' }
        @{ Key='HERMES_API_KEY';                 Bytes=32; Mode='hex' }
        @{ Key='HERMES_DASHBOARD_TOKEN';         Bytes=32; Mode='hex' }
        @{ Key='NEXTAUTH_SECRET';                Bytes=32; Mode='b64' }
        @{ Key='LINKWARDEN_DB_PASSWORD';         Bytes=20; Mode='hex' }
        @{ Key='DB_PASSWORD';                    Bytes=20; Mode='hex' }
        @{ Key='TOR_VNC_PW';                     Bytes=12; Mode='hex' }
    )
    foreach ($s in $genSpecs) {
        if ($Reconfigure -or (Test-Placeholder $envMap[$s.Key])) {
            $envMap[$s.Key] = if ($s.Mode -eq 'hex') {
                New-HexSecret -Bytes $s.Bytes
            } else {
                New-Base64Secret -Bytes $s.Bytes
            }
        }
    }
    if (Test-Placeholder $envMap['HERMES_WORKSPACE_PASSWORD']) {
        $envMap['HERMES_WORKSPACE_PASSWORD'] = New-HexSecret 12
    }
    Ok 'Secrets generated.'

    # ---- write .env back -------------------------------------------------
    Write-EnvFile $EnvFile $envMap

    return [pscustomobject]@{
        Env             = $envMap
        Stack           = $stack
        Profiles        = $profiles
        CustomServices  = $customServices
        UseTunnel       = $useTunnel
        HasAi           = $hasAi
        HasMedia        = $hasMedia
        GpuMode         = $gpuMode
    }
}

# ---------------------------------------------------------------------------
# Template rendering (Caddy / Authelia / SearXNG).
# Kept logically identical to the previous wizard.
# ---------------------------------------------------------------------------
function Resolve-Template {
    param([string]$TemplatePath, [string]$OutputPath, $Env)
    if (-not (Test-Path $TemplatePath)) { return }
    $text = Get-Content $TemplatePath -Raw
    $text = $text.Replace('__SEARXNG_SECRET_KEY__',              [string]$Env['SEARXNG_SECRET_KEY'])
    $text = $text.Replace('__AUTHELIA_JWT_SECRET__',             [string]$Env['AUTHELIA_JWT_SECRET'])
    $text = $text.Replace('__AUTHELIA_STORAGE_ENCRYPTION_KEY__', [string]$Env['AUTHELIA_STORAGE_ENCRYPTION_KEY'])
    foreach ($k in $Env.Keys) {
        $needle = '${' + $k + '}'
        $text = $text.Replace($needle, [string]$Env[$k])
    }
    Set-Content -Path $OutputPath -Value $text -Encoding UTF8
}

function Write-LocalOnlyCaddyfile {
    param([string]$OutputPath, $Env)
    $torPw   = [string]$Env['TOR_VNC_PW']
    $torAuth = [string]$Env['TOR_BASIC_AUTH']
    $content = @"
# Caddy reverse proxy — LOCAL-ONLY MODE
# DOMAIN is empty in .env, so instead of *.<your-domain> we serve every
# service at http://<sub>.localhost. *.localhost auto-resolves to 127.0.0.1
# in all modern browsers + OSes (RFC 6761), so no hosts file, no DNS, no
# Cloudflare needed — just open http://photos.localhost, http://chat.localhost,
# etc., and Caddy on :80 proxies to the right container.
#
# LAN-only trust assumed — no Authelia gate on these routes. Switch to
# tunnel mode in the wizard (Step 2) if you want SSO + public access.

{
    auto_https off
    http_port 80
}

# ===== INFRASTRUCTURE =====
http://hub.localhost {
    reverse_proxy heimdall-media:80
}

http://portainer.localhost {
    reverse_proxy Portainer:9000
}

http://qdrant.localhost {
    reverse_proxy qdrant:6333
}

http://auth.localhost {
    reverse_proxy Authelia:9091
}

# ===== TOOLS =====
http://tool.localhost {
    reverse_proxy host.docker.internal:8890
}

http://search.localhost {
    reverse_proxy searxng:8080
}

# Tor zero-click auto-login (basic-auth injected, kasm form skipped).
http://tor.localhost {
    @root path /
    redir @root /vnc.html?username=kasm_user&password=$torPw&autoconnect=true&resize=remote 302
    reverse_proxy https://host.docker.internal:6901 {
        transport http {
            tls_insecure_skip_verify
        }
        header_up Authorization "Basic $torAuth"
    }
}

# ===== AI =====
http://chat.localhost {
    reverse_proxy host.docker.internal:9002
}

http://hermes.localhost {
    reverse_proxy hermes-workspace:3000
}

http://n8n.localhost {
    reverse_proxy host.docker.internal:5678
}

http://vane.localhost {
    reverse_proxy vane:3000
}

http://research.localhost {
    reverse_proxy local-deep-research:5000
}

# AI host services (no docker container in the standard compose — these
# routes 502 until you run flux/pony/voice/ltx natively on the host).
http://flux.localhost {
    reverse_proxy host.docker.internal:9020
}

http://pony.localhost {
    reverse_proxy host.docker.internal:9021
}

http://voice.localhost {
    reverse_proxy host.docker.internal:7861
}

http://ltx.localhost {
    reverse_proxy host.docker.internal:9022
}

# ===== MEDIA =====
http://movie.localhost {
    reverse_proxy host.docker.internal:9014
}

http://music.localhost {
    reverse_proxy host.docker.internal:4533
}

http://file.localhost {
    reverse_proxy host.docker.internal:8095
}

http://photos.localhost {
    reverse_proxy immich-server:2283
}

# Catch-all: any *.localhost we didn't map gets a friendly hint.
:80 {
    respond "Homelab - local-only mode. Open http://hub.localhost/ for the dashboard." 200
}
"@
    Set-Content -Path $OutputPath -Value $content -Encoding UTF8
}

function Render-Templates {
    param($Env, $StateBlob)

    if (-not $StateBlob.SEARXNG_SECRET_KEY)            { $StateBlob.SEARXNG_SECRET_KEY            = New-HexSecret 32 }
    if (-not $StateBlob.AUTHELIA_JWT_SECRET)           { $StateBlob.AUTHELIA_JWT_SECRET           = New-HexSecret 32 }
    if (-not $StateBlob.AUTHELIA_STORAGE_ENCRYPTION_KEY) {
        # We're generating a brand-new storage encryption key. If a stale
        # Authelia SQLite db exists, it was encrypted with the (now-lost)
        # previous key. Wipe it so Authelia re-initialises cleanly. Authelia
        # data is just session/2FA state — nothing irreplaceable on a fresh
        # install. users_database.yml is separate and survives.
        $autheliaDb = Join-Path $ProjectRoot 'persistent-storage/do-not-delete/authelia/db.sqlite3'
        if (Test-Path $autheliaDb) {
            Remove-Item $autheliaDb -Force -ErrorAction SilentlyContinue
            Dim '  Wiped stale Authelia db.sqlite3 (encryption key was regenerated).'
        }
        $StateBlob.AUTHELIA_STORAGE_ENCRYPTION_KEY = New-HexSecret 32
    }

    $renderEnv = [ordered]@{}
    foreach ($k in $Env.Keys) { $renderEnv[$k] = $Env[$k] }
    $renderEnv['SEARXNG_SECRET_KEY']              = $StateBlob.SEARXNG_SECRET_KEY
    $renderEnv['AUTHELIA_JWT_SECRET']             = $StateBlob.AUTHELIA_JWT_SECRET
    $renderEnv['AUTHELIA_STORAGE_ENCRYPTION_KEY'] = $StateBlob.AUTHELIA_STORAGE_ENCRYPTION_KEY
    $torCred = "kasm_user:" + [string]$Env['TOR_VNC_PW']
    $renderEnv['TOR_BASIC_AUTH'] = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($torCred))

    if ([string]::IsNullOrWhiteSpace($Env['DOMAIN'])) {
        Write-LocalOnlyCaddyfile -OutputPath (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/caddy/Caddyfile') -Env $renderEnv
    } else {
        Resolve-Template `
            (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/caddy/Caddyfile.tmpl') `
            (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/caddy/Caddyfile') `
            $renderEnv
    }
    # Authelia rejects an empty session.cookies.domain — and 'localhost'
    # alone, because it needs at least one period. In local-only mode
    # DOMAIN is intentionally blank, so substitute 'homelab.local' just
    # for the Authelia render. Authelia then boots cleanly with the
    # .homelab.local hostnames; they go unused because the local-only
    # Caddyfile doesn't proxy through Authelia.
    $autheliaEnv = [ordered]@{}
    foreach ($k in $renderEnv.Keys) { $autheliaEnv[$k] = $renderEnv[$k] }
    if ([string]::IsNullOrWhiteSpace($autheliaEnv['DOMAIN'])) {
        $autheliaEnv['DOMAIN'] = 'homelab.local'
    }
    Resolve-Template `
        (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/authelia/configuration.yml.tmpl') `
        (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/authelia/configuration.yml') `
        $autheliaEnv
    Resolve-Template `
        (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/searxng/settings.yml.tmpl') `
        (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/searxng/settings.yml') `
        $renderEnv

    $usersExample = Join-Path $ProjectRoot 'persistent-storage/do-not-delete/authelia/users_database.yml.example'
    $usersFile    = Join-Path $ProjectRoot 'persistent-storage/do-not-delete/authelia/users_database.yml'
    if (-not (Test-Path $usersFile) -and (Test-Path $usersExample)) {
        Copy-Item $usersExample $usersFile
    }
}

# ---------------------------------------------------------------------------
# Repair-BindPaths: docker bind-mounts that target FILES on the host will
# silently auto-create an empty DIRECTORY at that path on Windows when the
# file doesn't exist, which then breaks the container. Wipe any such
# stray directories so the next render/copy produces a real file.
# ---------------------------------------------------------------------------
function Repair-BindPaths {
    $bindFiles = @(
        (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/caddy/Caddyfile')
        (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/authelia/configuration.yml')
        (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/authelia/users_database.yml')
        (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/searxng/settings.yml')
        (Join-Path $ProjectRoot 'persistent-storage/do-not-delete/filebrowser/settings.json')
    )
    foreach ($p in $bindFiles) {
        if (Test-Path $p -PathType Container) {
            Remove-Item $p -Recurse -Force
            Dim "  Repaired bind path: removed stray directory at $p"
        }
    }

    # n8n persists its encryption key to .n8n/config on first boot. If an
    # earlier run let n8n boot with literal '__GENERATE_32_BYTE_HEX__' from a
    # placeholder .env, its saved key won't match the (now-regenerated) one
    # in .env. Wipe so n8n re-initializes with the current N8N_ENCRYPTION_KEY.
    $n8nConfig = Join-Path $ProjectRoot 'persistent-storage/n8n/n8n_storage/config'
    if (Test-Path $n8nConfig -PathType Leaf) {
        $cfg = Get-Content $n8nConfig -Raw -ErrorAction SilentlyContinue
        if ($cfg -match '__GENERATE_' -or $cfg -match 'CHANGE_ME') {
            Remove-Item $n8nConfig -Force
            Dim '  Wiped stale n8n config (had placeholder encryption key baked in).'
        }
    }
}

# ---------------------------------------------------------------------------
# Ensure-AutheliaUser: pulls the authelia image (if needed), generates a
# strong random password + argon2 hash, and writes users_database.yml so
# Authelia actually boots. No-op if a real hash is already in place.
# Password is stored in .env as AUTHELIA_ADMIN_PASSWORD for later recovery.
# ---------------------------------------------------------------------------
function Ensure-AutheliaUser {
    param($EnvMap)

    $usersFile    = Join-Path $ProjectRoot 'persistent-storage/do-not-delete/authelia/users_database.yml'
    $usersExample = Join-Path $ProjectRoot 'persistent-storage/do-not-delete/authelia/users_database.yml.example'

    if (-not (Test-Path $usersFile -PathType Leaf) -and (Test-Path $usersExample)) {
        Copy-Item $usersExample $usersFile
    }
    if (-not (Test-Path $usersFile -PathType Leaf)) {
        Err '  Cannot find users_database.yml.example to bootstrap Authelia user.'
        return
    }

    $contents = Get-Content $usersFile -Raw
    if ($contents -notmatch '__ARGON2_HASH_REPLACE_ME__') {
        # Hash already real, nothing to do.
        return
    }

    Dim '  Generating Authelia admin argon2 hash (may pull authelia image first)...'
    $password = New-HexSecret -Bytes 12
    $hashOutput = (& docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password $password) 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Err '  Authelia hash generation failed. Authelia may not start.'
        Dim "  $hashOutput"
        return
    }

    $hashMatch = [regex]::Match($hashOutput, '\$argon2[a-z]+\$[^\s]+')
    if (-not $hashMatch.Success) {
        Err '  Could not parse argon2 hash from authelia output. Authelia may not start.'
        Dim "  $hashOutput"
        return
    }
    $hash = $hashMatch.Value

    # Use .Replace() (literal) — NOT -replace — because the hash contains
    # `$` characters that would be interpreted as backreferences.
    $newContents = $contents.Replace('__ARGON2_HASH_REPLACE_ME__', $hash)
    Set-Content $usersFile $newContents -Encoding UTF8

    $EnvMap['AUTHELIA_ADMIN_PASSWORD'] = $password
    Write-EnvFile $EnvFile $EnvMap

    Ok "Authelia admin user 'admin' configured."
    Dim "  Password: $password   (also saved in .env as AUTHELIA_ADMIN_PASSWORD)"
}

# ---------------------------------------------------------------------------
# Ensure-HeimdallTiles: rewrites Heimdall's start-page tile URLs in
# app.sqlite based on the tile domain captured in Step 2b of the wizard.
#
#   $TileDomain non-empty  ->  https://chat.<dom>, https://movie.<dom>, ...
#   $TileDomain empty      ->  http://chat.localhost, http://photos.localhost, ...
#                              (resolved by Caddy's local-mode vhosts on :80)
#
# The rewrite is idempotent and gated: it only fires while at least one
# tile URL still contains the shipped "homelab.local" placeholder, so user
# customizations are never clobbered, and re-runs are no-ops.
#
# Uses docker (alpine:3.20 + apk add sqlite) so we don't need sqlite3
# on the host — same pattern Ensure-AutheliaUser uses for argon2.
# ---------------------------------------------------------------------------
function Ensure-HeimdallTiles {
    param([string]$TileDomain = '')

    $dbPath = Join-Path $ProjectRoot 'persistent-storage/do-not-delete/heimdall/config/www/app.sqlite'
    if (-not (Test-Path $dbPath -PathType Leaf)) {
        Dim '  Heimdall DB not present yet — tile rewrite will run after first heimdall boot.'
        return
    }

    $dbDir  = Split-Path $dbPath
    $dbName = Split-Path $dbPath -Leaf
    $tmpSql = Join-Path $dbDir '.heimdall-rewrite.sql'

    # Probe: how many tiles still hold the maintainer's placeholder?
    $probeRaw = (& docker run --rm -v "${dbDir}:/data" alpine:3.20 sh -c "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /data/$dbName ""SELECT COUNT(*) FROM items WHERE url LIKE '%homelab.local%';""") 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Err '  Could not probe Heimdall DB (docker sqlite3 failed). Skipping tile rewrite.'
        Dim "  $probeRaw"
        return
    }
    $count = 0
    [int]::TryParse(($probeRaw.Trim() -split "`n" | Select-Object -Last 1).Trim(), [ref]$count) | Out-Null
    if ($count -eq 0) {
        Dim '  Heimdall tiles already customized — leaving them alone.'
        return
    }

    # Build the per-tile URL map. id values come from the shipped app.sqlite
    # seed; if a user wipes and re-adds tiles, ids will be different and the
    # homelab.local probe above will return 0, so we never reach this branch.
    $lines = @()
    if ([string]::IsNullOrWhiteSpace($TileDomain)) {
        # LOCAL MODE: route everything through Caddy's *.localhost vhosts
        # (see Write-LocalOnlyCaddyfile). *.localhost auto-resolves to
        # 127.0.0.1 in every modern OS/browser, so no DNS or hosts file
        # required.
        $sub = [ordered]@{
            1 = 'chat'; 2 = 'movie'; 3 = 'music'; 4 = 'file'; 5 = 'tool'
            6 = 'flux'; 7 = 'voice'; 8 = 'ltx'
            9 = 'hermes'; 10 = 'n8n'; 11 = 'hermes'; 12 = 'n8n'
        }
        foreach ($id in $sub.Keys) {
            $lines += "UPDATE items SET url='http://$($sub[$id]).localhost' WHERE id=$id;"
        }
    } else {
        # ONLINE MODE: <subdomain>.<TileDomain> matching the Caddyfile vhosts.
        $sub = [ordered]@{
            1 = 'chat'; 2 = 'movie'; 3 = 'music'; 4 = 'file'; 5 = 'tool'
            6 = 'flux'; 7 = 'voice'; 8 = 'ltx'
            9 = 'hermes'; 10 = 'n8n'; 11 = 'hermes'; 12 = 'n8n'
        }
        foreach ($id in $sub.Keys) {
            $lines += "UPDATE items SET url='https://$($sub[$id]).$TileDomain' WHERE id=$id;"
        }
    }

    Set-Content -Path $tmpSql -Value ($lines -join "`n") -Encoding ASCII
    try {
        $applyRaw = (& docker run --rm -v "${dbDir}:/data" alpine:3.20 sh -c "apk add --no-cache sqlite >/dev/null 2>&1 && sqlite3 /data/$dbName "".read /data/.heimdall-rewrite.sql""") 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $target = if ($TileDomain) { "https://*.$TileDomain" } else { 'http://*.localhost' }
            Ok "Heimdall tiles rewritten -> $target ($count tile(s) updated)."
        } else {
            Err 'Heimdall tile rewrite failed (docker sqlite3 returned non-zero).'
            Dim "  $applyRaw"
        }
    } finally {
        Remove-Item $tmpSql -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Ensure-EnvSecrets: silently generate strong random values for any env keys
# still holding their placeholder (`__GENERATE_*__` / `__CHANGE_ME__`).
# Returns $true if any secret was written.
# ---------------------------------------------------------------------------
function Ensure-EnvSecrets {
    param($EnvMap)
    $genSpecs = @(
        @{ Key='POSTGRES_PASSWORD';              Bytes=24; Mode='hex' }
        @{ Key='N8N_ENCRYPTION_KEY';             Bytes=32; Mode='hex' }
        @{ Key='N8N_USER_MANAGEMENT_JWT_SECRET'; Bytes=32; Mode='hex' }
        @{ Key='HERMES_API_KEY';                 Bytes=32; Mode='hex' }
        @{ Key='HERMES_DASHBOARD_TOKEN';         Bytes=32; Mode='hex' }
        @{ Key='NEXTAUTH_SECRET';                Bytes=32; Mode='b64' }
        @{ Key='LINKWARDEN_DB_PASSWORD';         Bytes=20; Mode='hex' }
        @{ Key='DB_PASSWORD';                    Bytes=20; Mode='hex' }
        @{ Key='TOR_VNC_PW';                     Bytes=12; Mode='hex' }
        @{ Key='HERMES_WORKSPACE_PASSWORD';      Bytes=12; Mode='hex' }
    )
    $changed = $false
    foreach ($s in $genSpecs) {
        if (Test-Placeholder $EnvMap[$s.Key]) {
            $EnvMap[$s.Key] = if ($s.Mode -eq 'hex') {
                New-HexSecret -Bytes $s.Bytes
            } else {
                New-Base64Secret -Bytes $s.Bytes
            }
            $changed = $true
        }
    }
    return $changed
}

# ---------------------------------------------------------------------------
# New-StateBlob: shape of .wizard-state.json. Used both by fresh installs
# and as the seed for Render-Templates.
# ---------------------------------------------------------------------------
function New-StateBlob {
    return [pscustomobject]@{
        SEARXNG_SECRET_KEY              = ''
        AUTHELIA_JWT_SECRET             = ''
        AUTHELIA_STORAGE_ENCRYPTION_KEY = ''
        profiles                        = @('ai','media')
        customServices                  = @()
        useTunnel                       = $false
        gpuMode                         = 'cpu'
        configured                      = $true
    }
}

# ---------------------------------------------------------------------------
# Compose start / stop.
# ---------------------------------------------------------------------------
function Start-Stack {
    param(
        [string[]]$Profiles,
        [bool]$UseTunnel,
        [string]$GpuMode = 'cpu',  # 'cpu' | 'nvidia' | 'amd' | 'native' (Mac, Metal)
        [string[]]$CustomServices = @()
    )

    # `--progress plain` forces line-by-line output instead of compose v2's
    # default TTY redraw renderer. When the wizard is launched from the
    # macOS .command launcher (or the Windows .bat one) compose's in-place
    # progress updates don't redraw cleanly and you end up with hundreds
    # of near-identical "[+] Running 20/24 ... Waiting 5.5s" lines for
    # every healthcheck wait. Plain output is one line per event.
    $arglist = @('compose', '--progress', 'plain', '-f', 'docker-compose.yml')
    switch ($GpuMode) {
        'nvidia' { $arglist += @('-f', 'docker-compose.nvidia.yml') }
        'amd'    { $arglist += @('-f', 'docker-compose.amd.yml') }
        'native' { $arglist += @('-f', 'docker-compose.ollama-native.yml') }
    }

    if ($CustomServices -and $CustomServices.Count -gt 0) {
        # CUSTOM mode: pass explicit service names positionally to `up`.
        # We bypass --profile and instead list the chosen services plus
        # the always-on core (which has no profile but doesn't auto-start
        # when other services are listed positionally).
        $coreServices = @('caddy','authelia','heimdall','portainer')
        $services = @($CustomServices) + $coreServices
        if ($UseTunnel) { $services += 'cloudflared' }
        # De-dup while preserving order.
        $services = $services | Select-Object -Unique
        $arglist += @('up','-d') + $services
    } else {
        $effective = @($Profiles)
        if ($UseTunnel) { $effective += 'tunnel' }
        foreach ($p in $effective) { $arglist += @('--profile', $p) }
        $arglist += @('up','-d')
    }

    G ''
    Dim ("  docker " + ($arglist -join ' '))
    G ''

    # Filter compose's per-event plain output. We keep `--progress plain`
    # (so events are stable line-per-event instead of a redrawing TTY) but
    # strip the noise.
    #
    # Drop: intermediate lifecycle events (Creating/Created/Starting/Waiting/
    #       Recreating/etc.) that produce 5+ lines per container and tell
    #       the user nothing actionable.
    # Keep + reformat with [OK]: terminal-success events (Started/Healthy/
    #       Pulled/Running) so each container shows one or two clean rows.
    # Keep + reformat with [!] : Error / Failed events so problems remain
    #       loud and obvious.
    # Pass through unchanged: anything we don't recognise - compose summary
    # lines, pull-progress (Downloading/Extracting), multi-line errors.
    $dropPattern = '^\s*(Container|Network|Volume)\s+.+?\s+(Creating|Created|Starting|Waiting|Recreating|Recreated|Stopping|Stopped|Removing|Removed)\s*$'
    $okPattern   = '^\s*(Container|Network|Volume)\s+(.+?)\s+(Started|Healthy|Pulled|Running)\s*$'
    $errPattern  = '^\s*(Container|Network|Volume)\s+(.+?)\s+(Error|Failed.*)\s*$'

    & docker @arglist 2>&1 | ForEach-Object {
        # Coerce both ErrorRecord (from native stderr) and string into a
        # single string for matching.
        $line = if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $_.ToString()
        } else {
            [string]$_
        }
        if ([string]::IsNullOrWhiteSpace($line)) { return }
        if ($line -match $dropPattern) { return }
        if ($line -match $okPattern) {
            Write-Host ('  [OK] ' + $matches[1] + ' ' + $matches[2] + ' - ' + $matches[3]) -ForegroundColor Green
        } elseif ($line -match $errPattern) {
            Write-Host ('  [!]  ' + $matches[1] + ' ' + $matches[2] + ' - ' + $matches[3]) -ForegroundColor Red
        } else {
            Write-Host $line
        }
    }

    if ($LASTEXITCODE -ne 0) {
        Err 'docker compose up failed.'
        exit $LASTEXITCODE
    }
    Ok 'Stack is up.'
}

# ---------------------------------------------------------------------------
# Get-OllamaGpuMode: best-effort GPU detection. Returns 'nvidia', 'amd',
# or 'cpu'. Used as the default for the first-run wizard and on every
# -StartOnly when no explicit choice has been persisted yet.
# ---------------------------------------------------------------------------
function Get-OllamaGpuMode {
    param([string]$OS = $script:OS)

    # macOS: Docker Desktop's Linux VM can't reach Metal, so containerised
    # Ollama is always CPU. But if the user has Ollama running NATIVELY on
    # the host (brew install / ollama.app), we can detect that and default
    # to 'native' mode — Open WebUI / LDR / Vane will be repointed at
    # host.docker.internal:11434 so they get Metal-accelerated inference.
    if ($OS -eq 'Mac') {
        try {
            $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
            if ($resp.StatusCode -eq 200) { return 'native' }
        } catch {}
        return 'cpu'
    }

    # NVIDIA: check whether docker has the nvidia runtime registered.
    try {
        $info = (& docker info --format '{{json .Runtimes}}' 2>$null) | Out-String
        if ($info -match '"nvidia"') { return 'nvidia' }
    } catch {}

    # Windows fallback: try nvidia-smi on the host.
    if ($OS -eq 'Windows') {
        try {
            $null = & nvidia-smi --query-gpu=name --format=csv,noheader 2>$null
            if ($LASTEXITCODE -eq 0) { return 'nvidia' }
        } catch {}
    }

    # AMD ROCm (Linux only — Docker Desktop on Windows doesn't expose AMD).
    if ($OS -eq 'Linux' -and (Test-Path '/dev/kfd')) { return 'amd' }

    return 'cpu'
}

# ---------------------------------------------------------------------------
# LLM picker (only runs if AI in stack and no models installed yet).
# ---------------------------------------------------------------------------
function Wait-Ollama {
    param([int]$TimeoutSeconds = 60)
    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        try {
            $null = Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 2
            return $true
        } catch {}
        Start-Sleep -Seconds 1
    }
    return $false
}

# ---------------------------------------------------------------------------
# Ensure-NativeOllamaInstalled: when the wizard's gpuMode is "native" (Mac
# Apple Silicon path), make sure the host-installed `ollama` CLI exists and
# the server is responding on http://127.0.0.1:11434 BEFORE we compose-up.
# Without this, Start-Stack succeeds (the overlay disables the in-container
# ollama) but Open WebUI / Local Deep Research / Vane / Hermes all try to
# reach host.docker.internal:11434 and find nothing, and the auto-pull step
# in Install-FirstLlm later fails too.
#
# Prefers Homebrew (clean CLI install + launchd integration). Falls back to
# downloading the official universal Ollama.app from GitHub Releases for
# Macs without brew. No-op on every non-Mac OS - the wizard only ever sets
# gpuMode to "native" on macOS.
# ---------------------------------------------------------------------------
function Ensure-NativeOllamaInstalled {
    param([string]$GpuMode)
    if ($GpuMode -ne 'native') { return }
    if ($script:OS -ne 'Mac') { return }

    $hasCli = $null -ne (Get-Command ollama -ErrorAction SilentlyContinue)

    if ($hasCli) {
        if (Wait-Ollama -TimeoutSeconds 3) {
            Ok 'Native ollama already installed and responding on :11434.'
            return
        }
        Dim '  Native ollama is installed but the API is silent. Starting it...'
        if (Get-Command brew -ErrorAction SilentlyContinue) {
            & brew services start ollama 2>$null | Out-Null
        }
        if (-not (Wait-Ollama -TimeoutSeconds 30)) {
            # Last resort: detached `ollama serve` so it survives this script.
            Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
        }
        if (Wait-Ollama -TimeoutSeconds 30) {
            Ok 'Native ollama started.'
        } else {
            Err 'Ollama is installed but the API did not come up within 60s.'
            Dim '  Try manually: brew services restart ollama   (or: ollama serve)'
        }
        return
    }

    # Not installed - install it.
    G ''
    Step 'Installing native ollama (Apple Metal-accelerated)' `
         'You picked NATIVE Ollama in Step 3b. The "ollama" CLI is not on this Mac yet, so we will install it now.'

    if (Get-Command brew -ErrorAction SilentlyContinue) {
        Dim '  Homebrew detected - using `brew install ollama` (recommended).'
        & brew install ollama
        if ($LASTEXITCODE -ne 0) {
            Err 'brew install ollama failed - see output above.'
            Dim '  Skipping native install. The stack will still come up, but Open'
            Dim '  WebUI / Hermes / Vane / LDR will have no LLM backend until you'
            Dim '  install ollama manually.'
            return
        }
        Dim '  Starting ollama as a background launchd service...'
        & brew services start ollama 2>$null | Out-Null
    } else {
        Dim '  Homebrew not found. Downloading the official Ollama Mac app from:'
        Dim '    https://github.com/ollama/ollama/releases/latest'
        $tmpDir  = Join-Path ([System.IO.Path]::GetTempPath()) ("eisa-ollama-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmpDir | Out-Null
        $zipPath = Join-Path $tmpDir 'Ollama-darwin.zip'
        try {
            Invoke-WebRequest -Uri 'https://github.com/ollama/ollama/releases/latest/download/Ollama-darwin.zip' `
                              -OutFile $zipPath -UseBasicParsing
        } catch {
            Err ("Download failed: " + $_.Exception.Message)
            Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
            return
        }
        Dim '  Extracting Ollama.app to /Applications ...'
        # ditto preserves macOS codesign + quarantine metadata better than unzip.
        & ditto -xk $zipPath '/Applications/'
        Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            Err 'Extracting to /Applications failed.'
            return
        }
        Dim '  Launching Ollama.app (first launch installs the CLI to /usr/local/bin'
        Dim '  and starts the background daemon)...'
        & open -a Ollama 2>$null
    }

    Dim '  Waiting for the native ollama API to come up at http://127.0.0.1:11434 ...'
    if (Wait-Ollama -TimeoutSeconds 90) {
        Ok 'Native ollama is up.'
    } else {
        Err 'Ollama is installed but the API did not respond within 90s.'
        Dim '  If you used the .app installer, look for a one-time "Install CLI"'
        Dim '  prompt in the Ollama app window and accept it, then re-run.'
    }
}

function Get-OllamaModelCount {
    try {
        $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 5
        $j = $resp.Content | ConvertFrom-Json
        if ($null -eq $j.models) { return 0 }
        return @($j.models).Count
    } catch { return 0 }
}

function Read-RecommendedModels {
    if (-not (Test-Path $RecommendedFile)) { return @() }
    $items = @()
    foreach ($line in Get-Content $RecommendedFile) {
        if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
        $parts = $line -split '\|', 2
        if ($parts.Count -ne 2) { continue }
        $items += [pscustomobject]@{
            Tier = $parts[0].Trim().ToUpper()
            Tag  = $parts[1].Trim()
        }
    }
    return $items
}

function Test-OllamaModelInstalled {
    param([string]$Tag)
    try {
        $resp = Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 5
        $j = $resp.Content | ConvertFrom-Json
        foreach ($m in @($j.models)) {
            if ($m.name -eq $Tag -or $m.model -eq $Tag) { return $true }
        }
    } catch {}
    return $false
}

# Pull a model into whichever Ollama is reachable on :11434. Tries, in order:
#   1. `docker exec -it ollama ollama pull <tag>` (in-container ollama)
#   2. `& ollama pull <tag>`                       (host ollama CLI - Mac native)
#   3. POST /api/pull                              (last-resort streaming API)
function Invoke-OllamaPull {
    param([Parameter(Mandatory)][string]$Tag)

    # Containerised ollama present?
    try {
        $null = & docker inspect -f '{{.Id}}' ollama 2>$null
        if ($LASTEXITCODE -eq 0) {
            & docker exec -it ollama ollama pull $Tag
            return ($LASTEXITCODE -eq 0)
        }
    } catch {}

    # Host ollama CLI?
    try {
        $null = & ollama --version 2>$null
        if ($LASTEXITCODE -eq 0) {
            & ollama pull $Tag
            return ($LASTEXITCODE -eq 0)
        }
    } catch {}

    # API fallback (no nice progress, but works headless).
    Dim '  Streaming pull via /api/pull (no progress bar)...'
    try {
        $body = @{ name = $Tag } | ConvertTo-Json -Compress
        Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/pull' `
            -Method Post -Body $body -ContentType 'application/json' `
            -UseBasicParsing -TimeoutSec 3600 | Out-Null
        return $true
    } catch {
        Err "  /api/pull failed: $($_.Exception.Message)"
        return $false
    }
}

function Install-FirstLlm {
    $managerName = if ($script:OS -eq 'Mac') {
        'MAC-HOMELAB-MANAGER.COMMAND -> [4] LLM Manager'
    } else {
        'WINDOWS-HOMELAB-MANAGER.BAT -> [4] LLM Manager'
    }
    Step 'Step 5 — Starter LLMs' 'Auto-installing two recommended models so you have something to chat with out of the box. This may take a few minutes per model (~5 GB each).'

    if (-not (Wait-Ollama -TimeoutSeconds 90)) {
        Err 'Ollama is not responding on http://127.0.0.1:11434. Skipping model install.'
        Dim "  You can run $managerName after Ollama is up."
        return
    }

    $starters = @(
        [pscustomobject]@{
            Tag     = 'huihui_ai/gemma-4-abliterated:e4b-q4_K'
            Title   = 'Gemma 4 (e4b, Q4_K) - abliterated'
            Purpose = 'General-purpose, uncensored AI. Use this for everyday chat,'
            Purpose2= 'writing, brainstorming, summarising, Q&A. Smaller + faster.'
        }
        [pscustomobject]@{
            Tag     = 'carstenuhlig/omnicoder-2-9b:q4_k_m'
            Title   = 'OmniCoder 2 (9B, Q4_K_M)'
            Purpose = 'Agentic + coding model. Use this when you want the LLM to'
            Purpose2= 'write/edit code, drive tools, or plan multi-step tasks.'
        }
    )

    foreach ($m in $starters) {
        G ''
        Dim '  ----------------------------------------------------------------'
        G  "  $($m.Title)"
        Dim "    $($m.Purpose)"
        Dim "    $($m.Purpose2)"
        Dim "    Tag: $($m.Tag)"
        Dim '  ----------------------------------------------------------------'

        if (Test-OllamaModelInstalled -Tag $m.Tag) {
            Ok "$($m.Tag) already installed — skipping."
            continue
        }

        if (Invoke-OllamaPull -Tag $m.Tag) {
            Ok "Installed $($m.Tag)"
        } else {
            Err "Failed to pull $($m.Tag). You can retry from $managerName."
        }
    }

    G ''
    Dim '  ----------------------------------------------------------------'
    G  '  Want a MONSTER uncensored model?'
    Dim '  ----------------------------------------------------------------'
    Dim '  These take much more VRAM (~16-24 GB) but are noticeably smarter'
    Dim '  than the starters. Pull from the LLM Manager when you have the'
    Dim '  hardware:'
    Dim ''
    Dim '    iaprofesseur/SuperGemma4-26b-uncensored-Q4'
    Dim '      26B-param Gemma 4 variant. Uncensored, strong reasoning,'
    Dim '      great for long-form writing and tougher Q&A.'
    Dim ''
    Dim '    fredrezones55/Qwen3.6-35B-A3B-Uncensored-HauhauCS-Aggressive:Q4'
    Dim '      35B-param Qwen 3.6 MoE (A3B active). Uncensored aggressive'
    Dim '      finetune; the heaviest-hitter on the recommended list.'
    Dim ''
    Dim "  Pull them from $managerName -> [4] LLM Manager -> [2] Pull a"
    Dim '  Recommended/Custom Model. Both are already in recommended_models.txt.'
}

# ---------------------------------------------------------------------------
# Final summary.
# ---------------------------------------------------------------------------
function Show-Summary {
    param($Result)
    G ''
    G '  ============================================================'
    G '   All done.'
    G '  ============================================================'
    G ''
    if ($Result.UseTunnel -and $Result.Env['DOMAIN']) {
        Dim "  Hosting mode: ONLINE  (Cloudflare tunnel on $($Result.Env['DOMAIN']))"
        Dim '                Apps reachable from anywhere via your subdomains.'
    } else {
        Dim '  Hosting mode: LOCAL ONLY  (LAN access only; nothing exposed publicly)'
    }
    if ($Result.HasAi) {
        $gpuLabel = switch ($Result.GpuMode) {
            'nvidia' { 'NVIDIA GPU (CUDA, in-container Ollama)' }
            'amd'    { 'AMD GPU (ROCm, in-container Ollama)' }
            'native' { 'NATIVE Ollama on macOS (Metal) — in-container ollama disabled' }
            default  { 'CPU only (in-container Ollama)' }
        }
        Dim "  GPU mode    : $gpuLabel"
    }
    G ''
    G '  Open these in your browser:'
    Dim '  (*.localhost auto-resolves to 127.0.0.1 in every modern browser —'
    Dim '   Caddy on :80 proxies each subdomain to the right container.)'
    G ''
    G '    Heimdall (start page)   http://hub.localhost'
    G '    Portainer               http://portainer.localhost'
    if ($Result.HasMedia) {
        G ''
        Dim '  MEDIA & PRODUCTIVITY'
        G '    Jellyfin (movies/TV)    http://movie.localhost'
        G '    Navidrome (music)       http://music.localhost'
        G '    Immich (photos/videos)  http://photos.localhost'
        G '    Filebrowser             http://file.localhost'
        G '    Omni Tools              http://tool.localhost'
        G '    Tor Browser (auto-login) http://tor.localhost/'
    }
    if ($Result.HasAi) {
        G ''
        Dim '  AI'
        G '    Open WebUI (chat)       http://chat.localhost'
        G '    SearXNG (search)        http://search.localhost'
        G '    Local Deep Research     http://research.localhost'
        G '    Vane                    http://vane.localhost'
        G '    Hermes Workspace        http://hermes.localhost'
        G '    n8n (workflows)         http://n8n.localhost'
        G '    Qdrant (vector DB)      http://qdrant.localhost'
        Dim '    Ollama API (direct)     http://localhost:11434  (API-only, no UI)'
        Dim '    Hermes Gateway (direct) http://localhost:8642   (API-only, no UI)'
    }
    if ($Result.UseTunnel -and $Result.Env['DOMAIN']) {
        $d = $Result.Env['DOMAIN']
        G ''
        Dim "  ONLINE - via Cloudflare tunnel at *.$d"
        G "    Heimdall   https://hub.$d"
        if ($Result.HasMedia) {
            G "    Jellyfin   https://movie.$d"
            G "    Navidrome  https://music.$d"
            G "    Immich     https://photos.$d"
            G "    Files      https://file.$d"
        }
        if ($Result.HasAi) {
            G "    Open WebUI https://chat.$d"
            G "    SearXNG    https://search.$d"
            G "    n8n        https://n8n.$d"
            G "    Hermes     https://hermes.$d"
        }
        G ''
        Dim '  ============================================================'
        G  "  PART B - Cloudflare Public Hostnames (do this now in your browser)"
        Dim '  ============================================================'
        G  ''
        G  "  Cloudflared is already running and connected to your tunnel."
        G  "  You now need to tell Cloudflare which subdomains route to it."
        G  ''
        G  "  Go back to your tunnel in https://dash.cloudflare.com/  ->  Networks"
        G  "  ->  Tunnels  ->  (your tunnel)  ->  'Public Hostname' tab."
        G  ''
        G  "  EASIEST PATH (one wildcard covers every service):"
        Dim '    Subdomain : *'
        Dim "    Domain    : $d"
        Dim '    Path      : (leave blank)'
        Dim '    Service   : Type=HTTP  ,  URL=caddy:80'
        Dim '    Click "Save hostname".'
        G  ''
        G  "  OR explicit (one Public Hostname per service - more granular):"
        Dim "    hub.$d         ->  HTTP  caddy:80   Heimdall (start page)"
        if ($Result.HasMedia) {
            Dim "    movie.$d       ->  HTTP  caddy:80   Jellyfin"
            Dim "    music.$d       ->  HTTP  caddy:80   Navidrome"
            Dim "    photos.$d      ->  HTTP  caddy:80   Immich"
            Dim "    file.$d        ->  HTTP  caddy:80   Filebrowser"
            Dim "    tor.$d         ->  HTTP  caddy:80   Tor Browser (SSO)"
            Dim "    tool.$d        ->  HTTP  caddy:80   Omni Tools"
        }
        if ($Result.HasAi) {
            Dim "    chat.$d        ->  HTTP  caddy:80   Open WebUI"
            Dim "    search.$d      ->  HTTP  caddy:80   SearXNG"
            Dim "    n8n.$d         ->  HTTP  caddy:80   n8n workflows"
            Dim "    hermes.$d      ->  HTTP  caddy:80   Hermes Workspace"
            Dim "    vane.$d        ->  HTTP  caddy:80   Vane AI engine"
            Dim "    research.$d    ->  HTTP  caddy:80   Local Deep Research"
            Dim "    qdrant.$d      ->  HTTP  caddy:80   Qdrant vector DB"
        }
        Dim "    portainer.$d   ->  HTTP  caddy:80   Portainer (SSO)"
        Dim "    auth.$d        ->  HTTP  caddy:80   Authelia login (REQUIRED)"
        G  ''
        G  "  NOTE: 'caddy:80' is the internal docker hostname of the reverse proxy."
        G  "        Cloudflared reaches it on the docker 'caddy' network. Do NOT"
        G  "        use http://localhost - that's a different machine from cloudflared's view."
        G  ''
        Dim '  Once those Public Hostnames are saved, your subdomains are live.'
        Dim "  Test:  https://hub.$d  (should show Heimdall)."
        if (Ask-YesNo '  Open the Cloudflare tunnels page now?' $false) {
            Open-Browser 'https://dash.cloudflare.com/'
        }
    }
    G ''
    Dim '  ------------------------------------------------------------'
    G '  Privacy at a glance:'
    Dim '    [+] Everything runs on YOUR machine. No cloud account required.'
    Dim '    [+] No telemetry, no analytics, no phone-home.'
    if ($Result.HasAi) {
        Dim '    [+] LLMs run locally via Ollama. Prompts never leave your network.'
        Dim '    [+] Searches go through SearXNG (no tracking, no profile building).'
    }
    if ($Result.UseTunnel) {
        Dim '    [!] Tunnel mode is ON: Cloudflare is in the request path for'
        Dim '        traffic from outside your LAN. LAN access stays direct.'
    } else {
        Dim '    [+] Local-only mode: nothing is exposed to the public internet.'
    }
    Dim '  ------------------------------------------------------------'
    G ''
    if ($script:OS -eq 'Mac') {
        Dim '  Tip: re-open MAC-HOMELAB-MANAGER.COMMAND -> pick [2] to start / [3] to stop.'
    } else {
        Dim '  Tip: re-open WINDOWS-HOMELAB-MANAGER.BAT -> pick [2] to start / [3] to stop.'
    }
    G ''
}

# ===========================================================================
# Main flow.
# ===========================================================================
Show-Logo

$script:OS = Get-OS

# Make sure Docker is installed and the engine is reachable. If not, this
# will offer to download + install Docker Desktop, then wait for the engine.
Ensure-Docker -OS $script:OS

$state  = Read-State
$envMap = Read-EnvFile $EnvFile

# -----------------------------------------------------------------------------
# Branch A: -StartOnly — invoked by the HOMELAB-MANAGER launchers when the
# user picks [2] Start Stack.
# SELF-HEALING. Every step that the first-run wizard does (without the
# interactive prompts) runs here too, so the stack comes up cleanly even
# if you skipped first-run, or if Docker silently created stray dirs at
# bind-file paths, or if the Authelia hash placeholder is still in place.
# -----------------------------------------------------------------------------
if ($StartOnly) {
    Step 'Self-heal: preparing the stack to come up cleanly' ''

    # 1. Bootstrap .env from .env.example if needed.
    if (-not (Test-Path $EnvFile)) {
        Copy-Item $EnvExample $EnvFile
        Dim '  Created .env from .env.example.'
        $envMap = Read-EnvFile $EnvFile
    }
    $exampleMap = Read-EnvFile $EnvExample
    foreach ($k in $exampleMap.Keys) {
        if (-not $envMap.Contains($k)) { $envMap[$k] = $exampleMap[$k] }
    }

    # 2. Fill any placeholder secrets in .env silently.
    if (Ensure-EnvSecrets -EnvMap $envMap) {
        Write-EnvFile $EnvFile $envMap
        Ok 'Filled in missing .env secrets.'
    }

    # 3. Wipe any directories Docker auto-created at bind-file paths.
    Repair-BindPaths

    # 4. Load / synth state blob.
    $stateBlob = if ($state) { $state } else { New-StateBlob }
    foreach ($k in @('SEARXNG_SECRET_KEY','AUTHELIA_JWT_SECRET','AUTHELIA_STORAGE_ENCRYPTION_KEY','profiles','customServices','useTunnel','gpuMode','configured')) {
        if (-not $stateBlob.PSObject.Properties[$k]) {
            $stateBlob | Add-Member -NotePropertyName $k -NotePropertyValue $null
        }
    }
    if (-not $stateBlob.profiles -or $stateBlob.profiles.Count -eq 0) {
        if (-not $stateBlob.customServices -or $stateBlob.customServices.Count -eq 0) {
            $stateBlob.profiles = @('ai','media')
        }
    }
    # Auto-detect tunnel: only enable if the user supplied a real token.
    $stateBlob.useTunnel = -not (Test-Placeholder $envMap['CLOUDFLARE_TUNNEL_TOKEN'])
    # Auto-detect GPU mode if not already persisted by first-run.
    # 'native' is the macOS Apple-Silicon path (host-installed ollama via
    # Homebrew + the docker-compose.ollama-native.yml overlay) - must be
    # in this allowlist or -StartOnly will silently overwrite the saved
    # choice with re-detection (which returns 'cpu' on Mac) and the
    # containerised ollama will be pulled / started instead.
    if (-not $stateBlob.gpuMode -or $stateBlob.gpuMode -notin @('cpu','nvidia','amd','native')) {
        $stateBlob.gpuMode = Get-OllamaGpuMode
        Dim "  Detected GPU mode: $($stateBlob.gpuMode.ToUpper())"
    }
    $stateBlob.configured = $true

    # 5. Render Caddyfile, Authelia configuration.yml, SearXNG settings.yml
    #    (also copies users_database.yml from .example if missing).
    Render-Templates -Env $envMap -StateBlob $stateBlob
    Ok 'Rendered Caddy / Authelia / SearXNG config from templates.'

    # 5b. Rewrite Heimdall start-page tile URLs from the maintainer's
    #     placeholders to whatever the user picked in Step 2b. Idempotent —
    #     no-ops once the placeholders are gone, so this is safe in -StartOnly.
    Ensure-HeimdallTiles -TileDomain $envMap['HEIMDALL_TILE_DOMAIN']

    # 6. Generate Authelia admin argon2 hash if users_database.yml still has
    #    the placeholder. Auto-pulls the authelia image on first run.
    Ensure-AutheliaUser -EnvMap $envMap

    # 7. Persist the (possibly updated) state.
    Write-State -State $stateBlob

    # 8. Start.
    $profiles  = @($stateBlob.profiles)
    $customSvc = @($stateBlob.customServices)
    $useTunnel = [bool]$stateBlob.useTunnel
    $gpuMode   = [string]$stateBlob.gpuMode
    if ($customSvc -and $customSvc.Count -gt 0) {
        $hasAi    = ($customSvc | Where-Object { $_ -in 'ollama','open-webui','searxng','local-deep-research','vane','hermes-agent','hermes-workspace','n8n' }).Count -gt 0
        $hasMedia = ($customSvc | Where-Object { $_ -in 'jellyfin','navidrome','immich-server','filebrowser','omni-tools','tor-browser' }).Count -gt 0
    } else {
        $hasAi    = $profiles -contains 'ai'
        $hasMedia = ($profiles -contains 'media') -or ($profiles -contains 'media-stream') -or ($profiles -contains 'productivity')
    }

    # In native mode the host needs ollama on :11434 BEFORE compose comes
    # up - otherwise Open WebUI / Hermes / LDR / Vane all start with their
    # OLLAMA_BASE_URL pointing at host.docker.internal:11434 and find nothing.
    Ensure-NativeOllamaInstalled -GpuMode $gpuMode

    Start-Stack -Profiles $profiles -UseTunnel $useTunnel -GpuMode $gpuMode -CustomServices $customSvc

    if ($hasAi -and (Get-OllamaModelCount) -eq 0) {
        Install-FirstLlm
    }

    Show-Summary -Result ([pscustomobject]@{
        Env       = $envMap
        HasAi     = $hasAi
        HasMedia  = $hasMedia
        UseTunnel = $useTunnel
        GpuMode   = $gpuMode
    })
    exit 0
}

# -----------------------------------------------------------------------------
# Branch B: full first-run wizard — invoked by the HOMELAB-MANAGER launchers
# when the user picks [1] First-Run Setup.
# -----------------------------------------------------------------------------
$result = Invoke-Wizard

# Load/extend the state blob and persist secrets + choices.
$stateBlob = if ($state) { $state } else {
    [pscustomobject]@{
        SEARXNG_SECRET_KEY             = ''
        AUTHELIA_JWT_SECRET            = ''
        AUTHELIA_STORAGE_ENCRYPTION_KEY = ''
        profiles                       = @()
        customServices                 = @()
        useTunnel                      = $false
        gpuMode                        = 'cpu'
        configured                     = $false
    }
}
foreach ($k in @('SEARXNG_SECRET_KEY','AUTHELIA_JWT_SECRET','AUTHELIA_STORAGE_ENCRYPTION_KEY','profiles','customServices','useTunnel','gpuMode','configured')) {
    if (-not $stateBlob.PSObject.Properties[$k]) {
        $stateBlob | Add-Member -NotePropertyName $k -NotePropertyValue $null
    }
}
$stateBlob.profiles       = $result.Profiles
$stateBlob.customServices = $result.CustomServices
$stateBlob.useTunnel      = $result.UseTunnel
$stateBlob.gpuMode        = $result.GpuMode
$stateBlob.configured     = $true

Repair-BindPaths
Render-Templates -Env $result.Env -StateBlob $stateBlob
Ensure-HeimdallTiles -TileDomain $result.Env['HEIMDALL_TILE_DOMAIN']
Ensure-AutheliaUser -EnvMap $result.Env
Write-State -State $stateBlob

if (-not $NoStart) {
    # If the user picked NATIVE in Step 3b on Mac, install + start the host
    # ollama before compose-up so the AI services (open-webui, hermes-agent,
    # local-deep-research, vane) can reach host.docker.internal:11434 from
    # inside their containers as soon as they boot.
    Ensure-NativeOllamaInstalled -GpuMode $result.GpuMode

    Start-Stack -Profiles $result.Profiles -UseTunnel $result.UseTunnel -GpuMode $result.GpuMode -CustomServices $result.CustomServices
}

if (-not $NoStart -and $result.HasAi) {
    if ((Get-OllamaModelCount) -eq 0) {
        Install-FirstLlm
    }
}

Show-Summary -Result $result

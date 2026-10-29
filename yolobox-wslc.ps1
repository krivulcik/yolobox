<#
.SYNOPSIS
  Build and (re)deploy yolobox with WSL containers (wslc) instead of docker compose.

.DESCRIPTION
  Mirrors docker-compose.yml: same Dockerfile, build args, env vars, ports and
  /workspace mount. SSH is published on 33333 by default.
  Put this file in the yolobox repo root, next to Dockerfile and .env.

  Settings come from .env.wsl (override with -EnvFile): shell env var > env file > default.

.EXAMPLE
  .\yolobox-wslc.ps1              # build image if missing, recreate container
  .\yolobox-wslc.ps1 -Build       # force image rebuild
  .\yolobox-wslc.ps1 -Connect     # deploy, then ssh in
  .\yolobox-wslc.ps1 -Down        # stop and remove container (workspace is kept)
  .\yolobox-wslc.ps1 -SkipWslConfig  # don't create/check %USERPROFILE%\.wslconfig
#>
[CmdletBinding()]
param(
    [string]$EnvFile = '.env.wsl',
    [int]$HostPort,                # SSH -> container :22   (default: HOST_PORT, else 33333)
    [int]$AppPort,                 # app -> container :3000 (default: APP_PORT, else 4444)
    [string]$ContainerName,
    [string]$WorkspacePath,
    [string]$Image,
    [switch]$Build,
    [switch]$Connect,
    [switch]$Down,
    [switch]$SkipWslConfig
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Get-Command wslc -ErrorAction SilentlyContinue)) {
    throw "wslc not found. Run 'wsl --update' (WSL 2.9.3+ required)."
}

# --- settings: env var > env file > default --------------------------------------
$dotEnv = @{}
if (Test-Path -LiteralPath $EnvFile) {
    foreach ($line in Get-Content -LiteralPath $EnvFile) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#') -or -not $t.Contains('=')) { continue }
        $k, $v = $t.Split('=', 2)
        $dotEnv[$k.Trim()] = $v.Trim().Trim('"').Trim("'")
    }
} else {
    Write-Warning "$EnvFile not found, using built-in defaults."
}
function Get-Setting([string]$Key, [string]$Default = '') {
    $e = [Environment]::GetEnvironmentVariable($Key)
    if ($e) { return $e }
    if ($dotEnv.ContainsKey($Key) -and $dotEnv[$Key]) { return $dotEnv[$Key] }
    return $Default
}

if (-not $HostPort)      { $HostPort      = [int](Get-Setting 'HOST_PORT' '33333') }
if (-not $AppPort)       { $AppPort       = [int](Get-Setting 'APP_PORT'  '4444') }
if (-not $ContainerName) { $ContainerName = Get-Setting 'CONTAINER_NAME' 'wsl-yolo-claudecode' }
if (-not $Image)         { $Image         = Get-Setting 'DOCKER_IMAGE'   'wsl-yoloimage' }
if (-not $WorkspacePath) {
    $WorkspacePath = Get-Setting 'WORKSPACE_PATH' (Join-Path $env:USERPROFILE "workspace\$ContainerName")
}
$YoloUser = Get-Setting 'YOLO_USERNAME' 'yolo'

# --- helpers --------------------------------------------------------------------
function Invoke-Wslc {
    & wslc @args
    if ($LASTEXITCODE -ne 0) { throw "wslc $($args -join ' ') failed (exit $LASTEXITCODE)" }
}
# Windows PowerShell 5.1 turns redirected stderr of native commands into errors,
# which $ErrorActionPreference = 'Stop' then throws. Run "quiet" calls with Continue.
function Invoke-Quiet {
    $ErrorActionPreference = 'Continue'
    $cmd, $rest = $args
    $out = & $cmd @rest 2>&1 | ForEach-Object { "$_" }
    $global:LASTEXITCODE = $LASTEXITCODE
    return ($out -join "`n")
}
function Test-Wslc { Invoke-Quiet wslc @args | Out-Null; return ($LASTEXITCODE -eq 0) }

function Remove-Box {
    if (Test-Wslc container inspect $ContainerName) {
        Write-Host "Removing existing container '$ContainerName'..."
        Invoke-Quiet wslc container stop $ContainerName | Out-Null
        if (-not (Test-Wslc container remove $ContainerName)) {
            Invoke-Wslc container rm $ContainerName
        }
    }
}

# wslc is young; only pass flags this installed version actually supports
$buildHelp = Invoke-Quiet wslc build --help
$runHelp   = Invoke-Quiet wslc run --help

# --- down -----------------------------------------------------------------------
if ($Down) { Remove-Box; Write-Host "Done. Workspace kept at $WorkspacePath"; return }

# --- .wslconfig: mirrored networking so `localhost` inside WSL distros reaches -----
#     the ports wslc publishes on Windows' 127.0.0.1 (does not affect wslc itself)
if (-not $SkipWslConfig) {
    $wslConfig = Join-Path $env:USERPROFILE '.wslconfig'
    if (-not (Test-Path -LiteralPath $wslConfig)) {
        Set-Content -LiteralPath $wslConfig -Encoding ASCII -Value "[wsl2]`r`nnetworkingMode=mirrored"
        Write-Host "Created $wslConfig with networkingMode=mirrored."
        $answer = Read-Host "WSL must restart to apply it (closes all open WSL distros). Run 'wsl --shutdown' now? [y/N]"
        if ($answer -match '^(y|yes)$') {
            wsl --shutdown
            Start-Sleep -Seconds 3
        } else {
            Write-Host "OK. Later run 'wsl --shutdown' and then this script again."
        }
    } elseif (-not (Select-String -LiteralPath $wslConfig -Pattern '^\s*networkingMode\s*=\s*mirrored' -Quiet)) {
        Write-Warning ("$wslConfig exists without networkingMode=mirrored, so 'localhost' in a WSL distro " +
                       "won't reach port $HostPort. Add it under [wsl2] yourself, or use -SkipWslConfig to hide this.")
    }
}

# --- build ----------------------------------------------------------------------
if ($Build -or -not (Test-Wslc image inspect $Image)) {
    Write-Host "Building image '$Image'..."
    $b = @('build', '-t', $Image)
    if ($buildHelp -match '--file')      { $b += '-f', 'Dockerfile' }
    if ($buildHelp -match '--build-arg') {
        $b += '--build-arg', "USERNAME=$YoloUser"
        $b += '--build-arg', "GITHUB_USERNAME=$(Get-Setting 'GITHUB_USERNAME')"
        $b += '--build-arg', "INSTALL_PI=$(Get-Setting 'INSTALL_PI' 'true')"
        # optional: only passed when set, otherwise the Dockerfile defaults apply
        foreach ($k in 'PI_SUBAGENTS_REPO', 'PI_SUBAGENTS_REF', 'PI_SEARXNG_REPO', 'PI_SEARXNG_REF') {
            $v = Get-Setting $k
            if ($v) { $b += '--build-arg', "$k=$v" }
        }
    } else {
        Write-Warning "This wslc has no --build-arg; Dockerfile ARG defaults will be used."
    }
    Invoke-Wslc @b .
}

# --- run ------------------------------------------------------------------------
$WorkspacePath = $WorkspacePath.TrimEnd('\', '/')                 # "...workspaces\" -> "...workspaces"
New-Item -ItemType Directory -Force -Path $WorkspacePath | Out-Null
$wsMount = (Resolve-Path -LiteralPath $WorkspacePath).Path -replace '\\', '/'   # wslc wants forward slashes

Remove-Box

$r = @('run', '-d', '--name', $ContainerName)
if ($runHelp -match '--hostname') { $r += '--hostname', $ContainerName }
$r += '-p', "${HostPort}:22", '-p', "${AppPort}:3000"
$r += '-v', "${wsMount}:/workspace"

# Runtime env vars read by the yolobox entrypoint (empty ones are skipped)
$runtimeVars = @(
    'HOST_UID', 'HOST_GID',
    'LLM_ENDPOINT', 'LLM_API_KEY', 'LLM_API',
    'SEARXNG_URL',
    'CLAUDE_LOCAL_LLM', 'CLAUDE_BASE_URL', 'CLAUDE_AUTH_TOKEN', 'CLAUDE_MODEL'
)
foreach ($k in $runtimeVars) {
    $v = Get-Setting $k
    if (-not $v) { continue }
    $v = $v -replace 'host\.docker\.internal', 'host.wslc.internal'   # Docker host alias -> wslc
    $r += '-e', "$k=$v"
}
$r += $Image

Write-Host "Starting '$ContainerName' (workspace: $wsMount)..."
Invoke-Wslc @r

# --- wait for sshd ----------------------------------------------------------------
$ready = $false
for ($i = 0; $i -lt 30 -and -not $ready; $i++) {
    try {
        $tcp = [Net.Sockets.TcpClient]::new()
        $ready = $tcp.ConnectAsync('127.0.0.1', $HostPort).Wait(1000) -and $tcp.Connected
        $tcp.Dispose()
    } catch { }
    if (-not $ready) { Start-Sleep -Seconds 1 }
}
if (-not $ready) { Write-Warning "SSH not reachable on $HostPort yet. Check: wslc container logs $ContainerName" }

# new container = new host key; drop the stale localhost entry
if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
    Invoke-Quiet ssh-keygen -R "[localhost]:$HostPort" | Out-Null
}

Write-Host ""
Write-Host "Ready:  ssh -p $HostPort $YoloUser@localhost"
Write-Host "Shell without SSH:  wslc exec -it $ContainerName su - $YoloUser"

if ($Connect) { & ssh -o StrictHostKeyChecking=accept-new -p $HostPort "$YoloUser@localhost" }

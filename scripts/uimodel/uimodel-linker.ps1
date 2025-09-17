# ---------------- Parameters ----------------
# Accepts paths plus flags to control prompting, saving, build, linking, watching, and debug output.
[CmdletBinding()]
param(
  [string] $LibraryPath,          # Path to the skyux-lib-uimodel root
  [string] $InfinityPath,         # Path to the Infinity SPA root
  [string] $AdditionalSpaPaths,   # Comma/semicolon list of extra SPA roots
  [string] $PackageName = "@blackbaud-internal/skyux-uimodel",  # Package name to npm link
  [switch] $SkipMissing,          # Skip (instead of error) when an additional SPA path is missing
  [switch] $NoPrompt,             # Non-interactive mode (requires saved config or passed paths)
  [switch] $SavePaths,            # Force save current resolved paths as defaults
  [switch] $NoSave,               # Prevent saving (overrides -SavePaths)
  [switch] $NoBuild,              # Skip build steps
  [switch] $NoLink,               # Skip linking steps
  [switch] $NoWatch,              # Skip starting the library watch
  [switch] $DebugPaths            # Output diagnostic path info
)

$ErrorActionPreference = 'Stop'

# ---------------- Config: location to store persistent defaults ----------------
$ConfigDir  = Join-Path $env:APPDATA 'SkyUXDev'
$ConfigFile = Join-Path $ConfigDir 'uimodel-link-config.json'

function Get-Config {
  # Reads previously saved JSON config; returns an empty psobject if not present or malformed
  if (Test-Path $ConfigFile) {
    try {
      return Get-Content $ConfigFile -Raw | ConvertFrom-Json
    } catch {
      Write-Warning "Config unreadable. Ignoring."
    }
  }
  New-Object psobject
}

function Save-Config($cfg) {
  # Persists current path settings unless -NoSave
  if ($NoSave) { return }
  if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir | Out-Null
  }
  $cfg | ConvertTo-Json -Depth 6 | Set-Content -Path $ConfigFile -Encoding UTF8
  Write-Host "Saved defaults: $ConfigFile" -ForegroundColor DarkGreen
}

# -------------- Sanitization: normalize user-entered paths ----------------
function Format-Path([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $null }
  $p = $p.Trim()
  # Normalize smart quotes to plain quotes
  $p = $p -replace '[“”]', '"' -replace "[‘’]", "'"
  # Strip matching surrounding single/double quotes
  if ($p.Length -ge 2) {
    if (
      ($p.StartsWith('"') -and $p.EndsWith('"')) -or
      ($p.StartsWith("'") -and $p.EndsWith("'"))
    ) {
      $p = $p.Substring(1, $p.Length - 2)
    }
  }
  # Remove trailing slashes and trim again
  $p = $p.Trim().TrimEnd('\','/')
  return $p
}

# ---------------- Helpers ----------------
function Read-Path($label, $current, [switch]$Required) {
  # Interactive acquisition of a path unless -NoPrompt
  if ($NoPrompt -and -not $current -and $Required) {
    throw "Missing required path: $label (NoPrompt)"
  }
  if ($NoPrompt) { return $current }

  $def = if ($current) { " [$current]" } else { "" }
  $val = Read-Host "$label path$def"
  if ([string]::IsNullOrWhiteSpace($val)) {
    $val = $current
  }

  $val = Format-Path $val
  if ($Required -and [string]::IsNullOrWhiteSpace($val)) {
    Write-Host "Value required." -ForegroundColor Yellow
    return Read-Path $label $current -Required:$true
  }
  return $val
}

function Normalize([string]$p) {
  # Resolve to absolute path when possible.
  if ([string]::IsNullOrWhiteSpace($p)) { return $null }
  try {
    (Resolve-Path $p -ErrorAction Stop).Path
  } catch {
    # If resolution fails (e.g. path not yet created) return original string.
    $p
  }
}

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Info($m) { Write-Host "  • $m" -ForegroundColor DarkGray }

function Exec($cmd, $cwd) {
  # Run a shell command in a working directory, fail hard on non-zero exit code.
  Write-Info "$cwd`> $cmd"
  Push-Location $cwd
  try {
    & $env:ComSpec /d /c $cmd
    if ($LASTEXITCODE -ne 0) {
      throw "Failed ($LASTEXITCODE): $cmd"
    }
  } finally {
    Pop-Location
  }
}

# ---------------- Load config ----------------
$cfg = Get-Config

# Safe fallback assignments (PowerShell 5.1 friendly - checks property existence first)
if ((-not $LibraryPath)        -and ($cfg | Get-Member -Name LibraryPath        -ErrorAction SilentlyContinue)) { $LibraryPath        = $cfg.LibraryPath }
if ((-not $InfinityPath)       -and ($cfg | Get-Member -Name InfinityPath       -ErrorAction SilentlyContinue)) { $InfinityPath       = $cfg.InfinityPath }
if ((-not $AdditionalSpaPaths) -and ($cfg | Get-Member -Name AdditionalSpaPaths -ErrorAction SilentlyContinue)) { $AdditionalSpaPaths = $cfg.AdditionalSpaPaths }

# Sanitize loaded config values
$LibraryPath        = Format-Path $LibraryPath
$InfinityPath       = Format-Path $InfinityPath
$AdditionalSpaPaths = Format-Path $AdditionalSpaPaths

# ---------------- Prompts (only if needed) ----------------
if (-not $LibraryPath)  { $LibraryPath  = Read-Path "UIModel library" $LibraryPath -Required }
if (-not $InfinityPath) { $InfinityPath = Read-Path "Infinity SPA"    $InfinityPath -Required }
if (-not $AdditionalSpaPaths -and -not $NoPrompt) {
  $AdditionalSpaPaths = Read-Path "Additional SPA paths (comma/semicolon, optional)" $AdditionalSpaPaths
}

# Final sanitize post-prompt
$LibraryPath        = Format-Path $LibraryPath
$InfinityPath       = Format-Path $InfinityPath
$AdditionalSpaPaths = Format-Path $AdditionalSpaPaths

if ($DebugPaths) {
  Write-Host "DEBUG Raw (post-sanitize):" -ForegroundColor Magenta
  Write-Host "  LibraryPath        = [$LibraryPath]"
  Write-Host "  InfinityPath       = [$InfinityPath]"
  Write-Host "  AdditionalSpaPaths = [$AdditionalSpaPaths]"
}

# ---------------- Save defaults? (prompt only first run or when changed) ----------------
$hasConfig = Test-Path $ConfigFile

# Extract previous values if config loaded (sanitize for fair comparison)
$prevLib = if ($cfg | Get-Member -Name LibraryPath        -ErrorAction SilentlyContinue) { Format-Path $cfg.LibraryPath }        else { $null }
$prevInf = if ($cfg | Get-Member -Name InfinityPath       -ErrorAction SilentlyContinue) { Format-Path $cfg.InfinityPath }       else { $null }
$prevAdd = if ($cfg | Get-Member -Name AdditionalSpaPaths -ErrorAction SilentlyContinue) { Format-Path $cfg.AdditionalSpaPaths } else { $null }
$prevPkg = if ($cfg | Get-Member -Name PackageName        -ErrorAction SilentlyContinue) { $cfg.PackageName }                    else { $null }

function _Norm([string]$v) { if ([string]::IsNullOrWhiteSpace($v)) { '' } else { $v } }

$pathsChanged =
  (-not $hasConfig) -or
  (_Norm $LibraryPath)        -ne (_Norm $prevLib) -or
  (_Norm $InfinityPath)       -ne (_Norm $prevInf) -or
  (_Norm $AdditionalSpaPaths) -ne (_Norm $prevAdd) -or
  (_Norm $PackageName)        -ne (_Norm $prevPkg)

$willSave = $false

if (-not $hasConfig) {
  if (-not $NoPrompt) {
    $ans = Read-Host "Save these as defaults? (y/N)"
    if ($ans -match '^(y|yes)$') { $willSave = $true }
  }
} elseif ($pathsChanged) {
  if (-not $NoPrompt) {
    $ans = Read-Host "Detected path changes. Update saved defaults? (y/N)"
    if ($ans -match '^(y|yes)$') { $willSave = $true }
  }
} else {
  if ($DebugPaths) { Write-Host "DEBUG: Config present and unchanged; skipping save prompt." -ForegroundColor DarkGray }
}

# Explicit overrides
if ($SavePaths -and -not $NoSave) { $willSave = $true }
if ($NoSave) { $willSave = $false }

if ($willSave) {
  $toSave = New-Object psobject -Property @{
    LibraryPath        = $LibraryPath
    InfinityPath       = $InfinityPath
    AdditionalSpaPaths = $AdditionalSpaPaths
    PackageName        = $PackageName
    Updated            = (Get-Date)
  }
  Save-Config $toSave
}

# ---------------- Normalize & validate ----------------
$LibraryPath  = Normalize $LibraryPath
$InfinityPath = Normalize $InfinityPath

if ($DebugPaths) {
  Write-Host "DEBUG Normalized:" -ForegroundColor Magenta
  Write-Host "  LibraryPath  => $LibraryPath"
  Write-Host "  InfinityPath => $InfinityPath"
}

if (-not (Test-Path $LibraryPath))  { throw "Library not found: $LibraryPath" }
if (-not (Test-Path $InfinityPath)) { throw "Infinity not found: $InfinityPath" }

$distUimodel = Join-Path $LibraryPath 'dist\uimodel'

# Parse additional SPA list (comma or semicolon separated)
$additional = @()
if ($AdditionalSpaPaths) {
  foreach ($raw in ($AdditionalSpaPaths -split '[,;]')) {
    $t = Format-Path ($raw.Trim())
    if ($t) { $additional += (Normalize $t) }
  }
}

if ($DebugPaths -and $additional.Count -gt 0) {
  Write-Host "DEBUG Additional SPA normalized paths:" -ForegroundColor Magenta
  $additional | ForEach-Object { Write-Host "  - $_" }
}

# ---------------- Build & link ----------------
if (-not $NoBuild) {
  Write-Step "Build UIModel (workspace)"
  Exec "npx ng build" $LibraryPath

  Write-Step "Build UIModel library project"
  Exec "npx ng build uimodel" $LibraryPath

  Write-Step "Build schematics (if applicable)"
  Exec "npm run skyux:build-schematics" $LibraryPath
} else {
  Write-Info "Skipping build (NoBuild)."
}

if (-not $NoLink) {
  Write-Step "npm link (library dist)"
  Exec "npm i" $distUimodel
  Exec "npm link" $distUimodel

  Write-Step "Link into Infinity"
  Exec "npm i" $InfinityPath
  Exec "npm link $PackageName" $InfinityPath

  if ($additional.Count -gt 0) {
    Write-Step "Link into additional SPAs"
    foreach ($spa in $additional) {
      if (Test-Path $spa) {
        Exec "npm i" $spa
        Exec "npm link $PackageName" $spa
      } elseif ($SkipMissing) {
        Write-Info "Skipping missing: $spa"
      } else {
        throw "SPA path not found: $spa"
      }
    }
  } else {
    Write-Info "No additional SPAs provided."
  }
} else {
  Write-Info "Skipping linking (NoLink)."
}

# ---------------- Launch processes ----------------
$launched = @()
if (-not $NoWatch) {
  Write-Step "Start UIModel library watch (new PowerShell window)"
  Start-Process powershell -ArgumentList "-NoProfile","-Command","cd `"$LibraryPath`"; npx ng build uimodel --watch"
  $launched += "UIModel watch"
} else {
  Write-Info "Skipping watch (NoWatch)."
}

Write-Host "`nDone." -ForegroundColor Green
if ($launched.Count -gt 0) {
  Write-Host "Started processes:" -ForegroundColor Cyan
  foreach ($p in $launched) { Write-Host " - $p" }
  Write-Host "Close their window to stop."
}
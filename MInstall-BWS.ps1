# Minimal installer for Bitwarden Secrets Manager CLI (bws) v1.0.0 (Windows x86_64)
# Downloads the zip and drops bws.exe into %LOCALAPPDATA%\Microsoft\WindowsApps

$ErrorActionPreference = "Stop"

$uri = "https://github.com/bitwarden/sdk-sm/releases/download/bws-v1.0.0/bws-x86_64-pc-windows-msvc-1.0.0.zip"
$destDir = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps"
$tmpZip  = Join-Path $env:TEMP "bws.zip"
$tmpDir  = Join-Path $env:TEMP "bws-extract"

# Clean temp
Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tmpDir | Out-Null

# Download
Invoke-WebRequest $uri -OutFile $tmpZip

# Extract
Expand-Archive $tmpZip $tmpDir -Force

# Find bws.exe (zip only contains one)
$bws = Get-ChildItem $tmpDir -Recurse -Filter "bws*.exe" | Select-Object -First 1
if (-not $bws) { throw "bws.exe not found in archive" }

# Copy to WindowsApps (already on PATH)
Copy-Item $bws.FullName (Join-Path $destDir "bws.exe") -Force

# Verify
& (Join-Path $destDir "bws.exe") --version

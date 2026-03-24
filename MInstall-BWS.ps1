# Minimal installer for Bitwarden Secrets Manager CLI (bws) via cargo

$ErrorActionPreference = "Stop"

# Ensure cargo is available
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "cargo is not installed or not in PATH. Please install Rust (e.g. via 'winget install Rustlang.Rustup')."
}

Write-Host "Installing bws via cargo..."
cargo install bws

# Ensure ~/.cargo/bin is in the PATH for the current session,
# since cargo typically installs binaries there.
$cargoBinPath = Join-Path $env:USERPROFILE ".cargo\bin"

if ($env:PATH -notmatch [regex]::Escape($cargoBinPath)) {
    $env:PATH = "$cargoBinPath;$env:PATH"
    Write-Host "Added $cargoBinPath to the current session's PATH."
}

# Verify
& bws --version

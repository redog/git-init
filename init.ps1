# Main entry point for the Git-Init script
param(
    [switch]$Reconfigure,
    [switch]$Reload
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import Modules
Import-Module (Join-Path $ScriptDir "APIKeys") -Force
Import-Module (Join-Path $ScriptDir "GitInit") -Force
Import-Module (Join-Path $ScriptDir "APIKeys" "KeyRotation") -Force

# Load configuration. JSON is canonical (shared with init.sh); .psd1 kept for back-compat.
$configCandidates = @(
    $env:GIT_INIT_CONFIG,
    (Join-Path $ScriptDir 'config.json'),
    (Join-Path $HOME    '.git-init.json'),
    (Join-Path $ScriptDir 'config.psd1'),
    (Join-Path $HOME    '.git-init.psd1')
) | Where-Object { $_ -and (Test-Path $_) }

$configPath = if ($configCandidates) { $configCandidates[0] } else { $null }

if (-not $configPath) {
    Write-Host "No git-init config found. Let's set one up." -ForegroundColor Cyan
    $defaultItem = 'Bitwarden Secrets Manager Service Account'
    $itemInput = Read-Host "Bitwarden vault item (name or UUID) holding BWS access token [$defaultItem]"
    if ([string]::IsNullOrWhiteSpace($itemInput)) { $itemInput = $defaultItem }

    $cliInput = Read-Host "BWS CLI path [bws]"
    if ([string]::IsNullOrWhiteSpace($cliInput)) { $cliInput = 'bws' }

    Write-Host "Your KeyMap needs at least a 'GitHub' entry mapping to GITHUB_ACCESS_TOKEN."
    Write-Host "List BWS secrets with: bws secret list"
    $ghId = Read-Host 'GitHub PAT secret UUID in BWS'

    $defaultPath = Join-Path $HOME '.git-init.json'
    $pathInput = Read-Host "Save config to [$defaultPath]"
    if ([string]::IsNullOrWhiteSpace($pathInput)) { $pathInput = $defaultPath }

    Initialize-APIKeysConfigFile -Path $pathInput -BwsTokenItem $itemInput -BwsCliPath $cliInput
    Add-APIKey -Name 'GitHub' -SecretId $ghId -Env @{ GITHUB_ACCESS_TOKEN = '$secret' } -Path $pathInput
    $configPath = $pathInput
}

if ($configPath) {
    Write-Host "Loading configuration from $configPath..."
    Import-APIKeysConfig -Path $configPath

    # Load Keys (this sets env vars like GITHUB_ACCESS_TOKEN)
    $shouldLoadKeys = $Reload
    if (-not $shouldLoadKeys) {
        $keyMap = Get-APIKeyMap
        if ($null -eq $keyMap -or $keyMap.Count -eq 0) {
            $shouldLoadKeys = $true
        }
        else {
            $missingKeys = $false
            foreach ($entry in $keyMap) {
                foreach ($envVar in $entry.Env.Keys) {
                    if (-not (Test-Path "Env:$envVar")) {
                        $missingKeys = $true
                        break
                    }
                }
                if ($missingKeys) { break }
            }
            if ($missingKeys) {
                $shouldLoadKeys = $true
            }
            else {
                Write-Host "API Keys already loaded. Use -Reload to force reload."
            }
        }
    }

    if ($shouldLoadKeys) {
        Write-Host "Loading API Keys..."
        Set-AllAPIKeys
    }
}
else {
    Write-Warning "Configuration file not loaded. API keys will not be available."
}

# Verify GitHub Token
if (-not $env:GITHUB_ACCESS_TOKEN) {
    Write-Error "GITHUB_ACCESS_TOKEN is not set. Please ensure config.psd1 maps a secret to this environment variable and that you have authenticated with Bitwarden."
    return
}

# Ensure git-credential-env exists on Linux/macOS
if ($IsLinux -or $IsMacOS) {
    $configDir = Join-Path $HOME ".config"
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }

    $helperScript = Join-Path $configDir "git-credential-env"
    if (-not (Test-Path $helperScript)) {
        $helperContent = @"
#!/usr/bin/env bash
set -euo pipefail
op=`${1:-}
while IFS= read -r line && [[ -n `$line ]]; do :; done
[[ `$op == get ]] || exit 0
token=`${GITHUB_ACCESS_TOKEN:-}
if [[ -z `$token ]]; then
    [[ -n `${GH_TOKEN_ID:-} ]] || { echo "GH_TOKEN_ID not set" >&2; exit 1; }
    token=`$(bws secret get "`$GH_TOKEN_ID" -o json | jq -r .value)
fi
echo "username=x-access-token"
echo "password=`$token"
"@
        Set-Content -Path $helperScript -Value $helperContent
        # Make it executable
        if (Get-Command chmod -ErrorAction SilentlyContinue) {
            chmod +x $helperScript
        }
    }
}

# Prompt user for action
$title = "Git-Init"
$message = "What would you like to do?"
$choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
    (New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&New repository', 'Create a new repository'),
    (New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Clone existing repository', 'Clone an existing repository'),
    (New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList 'Continue to &shell', 'Exit the script and continue to shell')
)

$choice = $Host.UI.PromptForChoice($title, $message, $choices, 0)

if ($choice -eq 0) {
    # Create new repo
    $repoName = Read-Host "Enter the name for the new repository"

    # Determine GitHub username
    $username = $null
    if (-not $Reconfigure) {
        $username = Get-GHUser
    }
    if ([string]::IsNullOrWhiteSpace($username)) {
        $username = Read-Host "Enter your GitHub username"
    }

    # Determine Name
    $name = $null
    if (-not $Reconfigure) {
        $name = git config --global user.name
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = Read-Host "Enter your full name"
    }

    # Determine Email
    $email = $null
    if (-not $Reconfigure) {
        $email = git config --global user.email
    }
    if ([string]::IsNullOrWhiteSpace($email)) {
        $email = Read-Host "Enter your email address"
    }

    $repo = New-GHRepository -RepoName $repoName
    if ($repo) {
        Write-Host "Repository '$($repo.full_name)' created successfully."
        Initialize-LocalGitRepository -RepoName $repoName -Username $username -Name $name -Email $email
    }
}
elseif ($choice -eq 1) {
    # Clone existing repo
    $repositories = @(Get-GHRepositories | Sort-Object)
    if ($repositories) {
        Write-Host "Select a repository to clone:"
        for ($i = 0; $i -lt $repositories.Count; $i++) {
            Write-Host "$($i + 1). $($repositories[$i])"
        }

        while ($true) {
            $selection = Read-Host "Enter repository number (1-$($repositories.Count))"
            if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $repositories.Count) {
                $selectedRepo = $repositories[[int]$selection - 1]
                break
            }
            Write-Warning "Invalid selection."
        }

        # Clone using credential helper to avoid prompts
        $helperScript = Join-Path $HOME ".config/git-credential-env"
        if ($IsLinux) {
            git -c credential.helper=$helperScript clone "https://github.com/$selectedRepo.git"
        }
        elseif ($IsMacOS) {
            git -c credential.helper=osxkeychain clone "https://github.com/$selectedRepo.git"
        }
        else {
            git -c credential.helper=manager clone "https://github.com/$selectedRepo.git"
        }

        $repoName = Split-Path $selectedRepo -Leaf
        if (Test-Path $repoName) {
            Push-Location $repoName
            if ($IsLinux) {
                git config credential.helper $helperScript
            }
            elseif ($IsMacOS) {
                git config credential.helper osxkeychain
            }
            else {
                git config credential.helper manager
            }
            git config remote.origin.url "https://github.com/$selectedRepo.git"
            Write-Host "Clone complete. Credential helper configured."
            Pop-Location
        } else {
            Write-Warning "Failed to clone repository. Please check the cloned repository."
        }
    } 
}
elseif ($choice -eq 2) {
    Write-Host "Continuing to shell..."
}

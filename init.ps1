# Main entry point for the Git-Init script
param(
    [switch]$Reconfigure,
    [switch]$Reload
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import Modules
Import-Module (Join-Path $ScriptDir "APIKeys") -Force
Import-Module (Join-Path $ScriptDir "GitInit") -Force

# Load configuration
$configPath = Join-Path $ScriptDir "config.psd1"
if (-not (Test-Path $configPath)) {
    $configPath = Join-Path $HOME ".git-init.psd1"
}

if (Test-Path $configPath) {
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
    Write-Warning "Configuration file not found (checked '$($ScriptDir)/config.psd1' and '$HOME/.git-init.psd1'). API keys might not be loaded."
}

# Verify GitHub Token
if (-not $env:GITHUB_ACCESS_TOKEN) {
    Write-Error "GITHUB_ACCESS_TOKEN is not set. Please ensure config.psd1 maps a secret to this environment variable and that you have authenticated with Bitwarden."
    exit 1
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
    $repositories = Get-GHRepositories | Sort-Object
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

        # Clone using authenticated URL to avoid prompts
        $authUrl = "https://x-access-token:$($env:GITHUB_ACCESS_TOKEN)@github.com/$selectedRepo.git"
        git clone $authUrl
        #git clone "https://github.com/$selectedRepo.git"
        $repoName = Split-Path $selectedRepo -Leaf
        $username = Get-GHUser
        if ((Test-Path $repoName ) -and ( -not [string]::IsNullOrWhiteSpace($username))) {
            Push-Location $repoName
            $cleanUrl = "https://$username@github.com/$selectedRepo.git"
            git remote set-url origin $cleanUrl
            Write-Host "Clone complete. Remote origin reset to clean URL."
            Pop-Location
        } else {
            Write-Warning "Could not reset remote URL. Please check the cloned repository."
        }
    } 
}
elseif ($choice -eq 2) {
    Write-Host "Continuing to shell..."
}

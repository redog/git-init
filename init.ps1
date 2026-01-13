# Main entry point for the Git-Init script
param([switch]$Reconfigure)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import Modules
Import-Module (Join-Path $ScriptDir "APIKeys") -Force
Import-Module (Join-Path $ScriptDir "GitInit") -Force

# Load configuration
$configPath = Join-Path $ScriptDir "config.psd1"
if (-not (Test-Path $configPath)) {
    $configPath = Join-Path $HOME ".git-init.ps1"
}

if (Test-Path $configPath) {
    Write-Host "Loading configuration from $configPath..."
    Import-ApiKeysConfig -Path $configPath

    # Load Keys (this sets env vars like GITHUB_ACCESS_TOKEN)
    Write-Host "Loading API Keys..."
    Set-AllApiKeys
}
else {
    Write-Warning "Configuration file config.psd1 not found. API keys might not be loaded."
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
    (New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Clone existing repository', 'Clone an existing repository')
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

        # Set-GitCredentialHelper # TODO: Implement this in GitInit module
        Write-Warning "Credential helper setup is not yet implemented."

        git clone "https://github.com/$selectedRepo.git"
    }
}

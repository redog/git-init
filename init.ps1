# Main entry point for the Git-Init script

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
    (New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList 'Create a new repository'),
    (New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList 'Clone an existing repository')
)

$choice = $Host.UI.PromptForChoice($title, $message, $choices, 0)

if ($choice -eq 0) {
    # Create new repo
    $repoName = Read-Host "Enter the name for the new repository"
    $username = Read-Host "Enter your GitHub username"
    $name = Read-Host "Enter your full name"
    $email = Read-Host "Enter your email address"

    $repo = New-GHRepository -RepoName $repoName
    if ($repo) {
        Write-Host "Repository '$($repo.full_name)' created successfully."
        Initialize-LocalGitRepository -RepoName $repoName -Username $username -Name $name -Email $email
    }
}
elseif ($choice -eq 1) {
    # Clone existing repo
    $repositories = Get-GHRepositories
    if ($repositories) {
        $repoChoices = $repositories | ForEach-Object { New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList $_ }
        $repoIndex = $Host.UI.PromptForChoice("Clone Repository", "Select a repository to clone", $repoChoices, 0)
        $selectedRepo = $repositories[$repoIndex]

        # Set-GitCredentialHelper # TODO: Implement this in GitInit module
        Write-Warning "Credential helper setup is not yet implemented."

        git clone "https://github.com/$selectedRepo.git"
    }
}

#requires -Commands bw, bws, git

# Main entry point for the Git-Init script
# This script will dot-source the module and execute the main logic.

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$ScriptDir/GitInit.psm1"

# Load configuration
$configPath = Join-Path $ScriptDir "config.psd1"
if (-not (Test-Path $configPath)) {
    $configPath = Join-Path $HOME ".git-init.ps1"
}

if (Test-Path $configPath) {
    $config = Import-PowerShellDataFile $configPath
}
else {
    Write-Warning "Configuration file config.psd1 not found."
    # You can define default values here if needed
    $config = @{}
}

# Set environment variables from config
$config.GetEnumerator() | ForEach-Object {
    [System.Environment]::SetEnvironmentVariable($_.Name, $_.Value, 'Process')
}

Write-Host "Configuration loaded."

Ensure-BWSession

$githubToken = Get-SecretValue -SecretId $env:GH_TOKEN_ID
if (-not $githubToken) {
    Write-Error "Failed to retrieve GitHub token. Exiting."
    exit 1
}
$env:GITHUB_ACCESS_TOKEN = $githubToken

# Prompt user for action
$title = "Git-Init"
$message = "What would you like to do?"
$choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
    (New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList '&Create a new repository'),
    (New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList 'C&lone an existing repository')
)

$choice = $Host.UI.PromptForChoice($title, $message, $choices, 0)

if ($choice -eq 0) {
    # Create new repo
    $repoName = Read-Host "Enter the name for the new repository"
    $username = Read-Host "Enter your GitHub username"
    $name = Read-Host "Enter your full name"
    $email = Read-Host "Enter your email address"
    $repo = New-GHRepository -RepoName $repoName -Token $githubToken
    if ($repo) {
        Write-Host "Repository '$($repo.full_name)' created successfully."
        Initialize-LocalGitRepository -RepoName $repoName -Username $username -Name $name -Email $email
    }
}
elseif ($choice -eq 1) {
    # Clone existing repo
    $repositories = Get-GHRepositories -Token $githubToken
    if ($repositories) {
        $repoChoices = $repositories | ForEach-Object { New-Object System.Management.Automation.Host.ChoiceDescription -ArgumentList $_ }
        $repoIndex = $Host.UI.PromptForChoice("Clone Repository", "Select a repository to clone", $repoChoices, 0)
        $selectedRepo = $repositories[$repoIndex]
        Set-GitCredentialHelper
        git clone "https://github.com/$selectedRepo.git"
    }
}
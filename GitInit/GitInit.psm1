# PowerShell module for Git-Init functionality
# This module contains functions for interacting with Bitwarden and GitHub.
Set-StrictMode -Version Latest

function Ensure-BWSession {
    <#
    .SYNOPSIS
    Ensures the user is logged in to Bitwarden and the vault is unlocked.
    #>
    [CmdletBinding()]
    param()

    try {
        $status = bw status | ConvertFrom-Json
    }
    catch {
        # bw command not found or other error
        Write-Error "Bitwarden CLI (bw) does not appear to be installed or is not in your PATH."
        return
    }

    if ($status.status -eq 'unauthenticated') {
        Write-Host "Logging in to Bitwarden..."
        if ($env:BW_CLIENTID -and $env:BW_CLIENTSECRET) {
            $env:BW_CLIENTSECRET | bw login --apikey --stdin
        }
        else {
            bw login
        }
        $status = bw status | ConvertFrom-Json
        if ($status.status -eq 'unauthenticated') {
            Write-Error "Bitwarden login failed."
            return
        }
    }

    if ($status.status -eq 'locked') {
        Write-Host "Unlocking Bitwarden vault..."
        $sessionKey = bw unlock --raw
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to unlock Bitwarden vault."
            return
        }
        $env:BW_SESSION = $sessionKey
        Write-Host "Vault unlocked."
    }
    else {
        Write-Host "Bitwarden vault is already unlocked."
    }
}

function Get-SecretValue {
    <#
    .SYNOPSIS
    Retrieves a secret value from Bitwarden Secrets Manager.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$SecretId
    )

    try {
        $secret = bws secret get $SecretId --raw | ConvertFrom-Json
        return $secret.value
    }
    catch {
        Write-Error "Failed to retrieve secret with ID '$SecretId'. Error: $_"
        return $null
    }
}

function Set-GitCredentialHelper {
    <#
    .SYNOPSIS
    Configures the Git credential helper based on the OS.
    #>
    [CmdletBinding()]
    param()

    if ($isWindows) {
        git config --global credential.helper manager
    }
    elseif ($isMac) {
        git config --global credential.helper osxkeychain
    }
    elseif ($isLinux) {
        $helperPath = Join-Path $HOME ".config/git-credential-env"
        if (-not (Test-Path $helperPath)) {
            $helperContent = "#!/usr/bin/env pwsh`n"
            $helperContent += "`$token = Get-SecretValue -SecretId `$env:GH_TOKEN_ID`n"
            $helperContent += "if (`$token) {`n"
            $helperContent += "    echo `"username=x-access-token`"`n"
            $helperContent += "    echo `"password=`$token`"`n"
            $helperContent += "}"
            New-Item -Path $helperPath -ItemType File -Value $helperContent -Force
            # This is not cross-platform, but the script is intended for Linux in this case
            /bin/bash -c "chmod +x $helperPath"
        }
        git config --global credential.helper $helperPath
    }
}

function Initialize-LocalGitRepository {
    <#
    .SYNOPSIS
    Initializes a new local Git repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoName,

        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [string]$Email
    )

    $repoDir = Join-Path -Path (Get-Location) -ChildPath $RepoName
    if (Test-Path $repoDir) {
        Write-Error "Directory '$RepoName' already exists."
        return
    }

    New-Item -ItemType Directory -Name $RepoName
    Set-Location $RepoName

    git init
    git config user.name $Name
    git config user.email $Email

    git remote add origin "https://github.com/$Username/$RepoName.git"

    "$RepoName by $Username" | Out-File -FilePath README.md
    Invoke-WebRequest -Uri "https://www.gnu.org/licenses/gpl-3.0.txt" -OutFile LICENSE

    git add .
    git commit -m "Initial commit"
    git branch -M main
    git push --set-upstream origin main
}

function Get-GHRepositories {
    <#
    .SYNOPSIS
    Fetches a list of repositories for the authenticated user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Token
    )

    $headers = @{
        "Authorization" = "token $Token"
    }

    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Headers $headers
        return $response.full_name
    }
    catch {
        Write-Error "Failed to fetch repositories. Error: $_"
        return $null
    }
}

function New-GHRepository {
    <#
    .SYNOPSIS
    Creates a new private GitHub repository.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RepoName,

        [Parameter(Mandatory=$true)]
        [string]$Token
    )

    $headers = @{
        "Authorization" = "token $Token"
        "Accept"        = "application/vnd.github.v3+json"
    }

    $body = @{
        name        = $RepoName
        description = "Created with the GitInit PowerShell script"
        private     = $true
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Method Post -Headers $headers -Body $body -ContentType "application/json"
        return $response
    }
    catch {
        $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json
        if ($errorResponse.errors[0].message -eq 'name already exists on this account') {
            Write-Warning "Repository name '$RepoName' is already taken."
        }
        else {
            Write-Error "Failed to create repository. Error: $($errorResponse.message)"
        }
        return $null
    }
}
# PowerShell module for Git-Init functionality
# This module contains functions for interacting with GitHub.
Set-StrictMode -Version Latest

function Get-GitHubAuthHeader {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:GITHUB_ACCESS_TOKEN)) {
        throw "GITHUB_ACCESS_TOKEN is not set. Run 'load_keys' or set the env var."
    }

    return @{
        Authorization = "Bearer $($env:GITHUB_ACCESS_TOKEN)"
        Accept        = "application/vnd.github.v3+json"
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
    param()

    $headers = Get-GitHubAuthHeader

    try {
        $response = Invoke-RestMethod `
            -Uri "https://api.github.com/user/repos" `
            -Headers $headers

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
        [Parameter(Mandatory)]
        [string]$RepoName
    )

    $headers = Get-GitHubAuthHeader

    $body = @{
        name        = $RepoName
        description = "Created with the GitInit PowerShell script"
        private     = $true
    } | ConvertTo-Json

    try {
        Invoke-RestMethod `
            -Uri "https://api.github.com/user/repos" `
            -Method Post `
            -Headers $headers `
            -Body $body `
            -ContentType "application/json"
    }
    catch {
        $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue

        if ($errorResponse?.errors?[0]?.message -eq 'name already exists on this account') {
            Write-Warning "Repository name '$RepoName' already exists."
        }
        else {
            Write-Error "Failed to create repository. Error: $($errorResponse.message ?? $_)"
        }
        return $null
    }
}

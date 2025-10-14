#requires -Version 7.0
Set-StrictMode -Version Latest

function Get-GitInitConfiguration {
    [CmdletBinding()]
    param()

    $configPath = $env:GIT_INIT_CONFIG
    if (-not $configPath) {
        $homeConfig = Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath '.git-init.ps1'
        if (Test-Path -LiteralPath $homeConfig) {
            $configPath = $homeConfig
        } else {
            $moduleConfig = Join-Path -Path $PSScriptRoot -ChildPath 'config.psd1'
            if (Test-Path -LiteralPath $moduleConfig) {
                $configPath = $moduleConfig
            }
        }
    }

    if (-not $configPath) {
        return @{}
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Configuration file '$configPath' was not found."
    }

    try {
        switch ([IO.Path]::GetExtension($configPath).ToLowerInvariant()) {
            '.psd1' { return Import-PowerShellDataFile -Path $configPath }
            '.json' {
                $json = Get-Content -LiteralPath $configPath -Raw
                return ConvertFrom-Json -InputObject $json -AsHashtable
            }
            default {
                $result = . $configPath
                if ($null -eq $result) {
                    return @{}
                }
                if ($result -is [hashtable]) {
                    return $result
                }
                throw "Configuration script '$configPath' must return a hashtable."
            }
        }
    } catch {
        throw "Failed to load configuration from '$configPath': $($_.Exception.Message)"
    }
}

function Ensure-CommandAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' is not available on PATH."
    }
}

function Invoke-ExternalCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [switch]$CaptureOutput,
        [switch]$IgnoreExitCode
    )

    $output = & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $IgnoreExitCode) {
        $joinedArguments = if ($Arguments) { $Arguments -join ' ' } else { '' }
        throw "Command '$FilePath $joinedArguments' failed with exit code $exitCode."
    }

    if ($CaptureOutput) {
        return $output
    }
}

function Ensure-BWSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    Ensure-CommandAvailable -Name 'bw'
    Ensure-CommandAvailable -Name 'bws'

    $status = $null
    try {
        $status = bw status | ConvertFrom-Json -AsHashtable
    } catch {
        throw "Unable to determine Bitwarden CLI status: $($_.Exception.Message)"
    }

    if ($null -eq $status -or $status.status -eq 'unauthenticated') {
        if ($env:BW_CLIENTID -and $env:BW_CLIENTSECRET) {
            Write-Host '🔑 Logging in to Bitwarden CLI using API key...'
            Invoke-ExternalCommand -FilePath 'bw' -Arguments @('login', '--apikey') | Out-Null
        } else {
            Write-Host '🔑 Logging in to Bitwarden CLI...'
            Invoke-ExternalCommand -FilePath 'bw' -Arguments @('login') | Out-Null
        }

        try {
            $status = bw status | ConvertFrom-Json -AsHashtable
        } catch {
            throw "Bitwarden CLI login failed: $($_.Exception.Message)"
        }

        if ($status.status -ne 'authenticated') {
            throw 'Bitwarden CLI login failed. Please verify your credentials.'
        }
    }

    if (-not $env:BW_SESSION) {
        Write-Host '🔐 Unlocking Bitwarden vault...'
        $sessionOutput = Invoke-ExternalCommand -FilePath 'bw' -Arguments @('unlock', '--raw') -CaptureOutput
        $session = ($sessionOutput | Select-Object -Last 1).Trim()
        if (-not $session) {
            throw 'Failed to unlock Bitwarden vault.'
        }
        $env:BW_SESSION = $session
        Write-Host '✅ Vault unlocked successfully. Session key stored in BW_SESSION.'
    }

    if (-not $env:BWS_ACCESS_TOKEN) {
        $accessTokenId = $Config.BWS_ACCESS_TOKEN_ID
        if (-not $accessTokenId) {
            throw 'BWS_ACCESS_TOKEN_ID is not defined in the configuration.'
        }

        Write-Host '=> Retrieving BWS access token from Bitwarden...'
        $tokenOutput = Invoke-ExternalCommand -FilePath 'bw' -Arguments @('get', 'password', $accessTokenId, '--session', $env:BW_SESSION) -CaptureOutput
        $token = ($tokenOutput | Select-Object -Last 1).Trim()
        if (-not $token) {
            throw 'Failed to retrieve BWS access token.'
        }
        $env:BWS_ACCESS_TOKEN = $token
    }

    if (-not $env:BW_CLIENTID -and $Config.BW_CLIENTID) {
        $env:BW_CLIENTID = $Config.BW_CLIENTID
    }

    if (-not $env:BW_CLIENTSECRET -and $Config.BW_API_KEY_ID) {
        Write-Host '=> Retrieving Bitwarden API key secret from Secrets Manager...'
        try {
            $secret = bws secret get $Config.BW_API_KEY_ID --output json | ConvertFrom-Json -AsHashtable
        } catch {
            throw "Failed to retrieve Bitwarden API key secret: $($_.Exception.Message)"
        }

        if (-not $secret -or -not $secret.value) {
            throw 'Bitwarden API key secret does not contain a value.'
        }

        $env:BW_CLIENTSECRET = [string]$secret.value
    }

    return $env:BW_SESSION
}

function Get-GitHubAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $tokenId = $Config.GH_TOKEN_ID
    if (-not $tokenId) {
        throw 'GH_TOKEN_ID is not defined in the configuration.'
    }

    Write-Host '=> Retrieving GitHub access token from Bitwarden Secrets Manager...'
    try {
        $secret = bws secret get $tokenId --output json | ConvertFrom-Json -AsHashtable
    } catch {
        throw "Failed to retrieve GitHub access token: $($_.Exception.Message)"
    }

    if (-not $secret -or -not $secret.value) {
        throw 'GitHub access token secret does not contain a value.'
    }

    return [string]$secret.value
}

function Read-MenuSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Options,
        [string]$Prompt = 'Please select an option:'
    )

    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Host "[$i] $($Options[$i])"
    }

    while ($true) {
        $choice = Read-Host $Prompt
        $index = 0
        if ([int]::TryParse($choice, [ref]$index)) {
            if ($index -ge 0 -and $index -lt $Options.Count) {
                return $index
            }
        }
        Write-Warning 'That was not a valid choice. Please try again.'
    }
}

function Get-GitConfigValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = Invoke-ExternalCommand -FilePath 'git' -Arguments $Arguments -CaptureOutput -IgnoreExitCode
    if (-not $output) {
        return $null
    }

    return ($output | Select-Object -Last 1).Trim()
}

function Get-GitHubRepositories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )

    $headers = @{
        Authorization = "token $Token"
        'User-Agent' = 'git-init-pwsh'
        Accept = 'application/vnd.github+json'
    }

    $repos = @()
    $page = 1

    while ($true) {
        $uri = "https://api.github.com/user/repos?per_page=100&page=$page"
        try {
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        } catch {
            throw "Failed to fetch repositories from GitHub: $($_.Exception.Message)"
        }

        if (-not $response) {
            break
        }

        $repos += $response
        if ($response.Count -lt 100) {
            break
        }

        $page++
    }

    return $repos | ForEach-Object { $_.full_name }
}

function New-GitHubRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Token,
        [string]$Description = 'Created with the GitHub API',
        [bool]$Private = $true
    )

    $headers = @{
        Authorization = "token $Token"
        'User-Agent' = 'git-init-pwsh'
        Accept = 'application/vnd.github+json'
    }

    $body = @{ name = $Name; description = $Description; private = $Private } | ConvertTo-Json

    try {
        $response = Invoke-WebRequest -Uri 'https://api.github.com/user/repos' -Method Post -Headers $headers -Body $body -ContentType 'application/json' -SkipHttpErrorCheck
    } catch {
        throw "Failed to create GitHub repository: $($_.Exception.Message)"
    }

    if ($response.StatusCode -eq 201) {
        Write-Host "Successfully created repository '$Name'."
        return
    }

    $errorMessage = $response.Content
    switch ($response.StatusCode) {
        422 {
            throw [System.InvalidOperationException]::new("Repository name '$Name' is already taken.")
        }
        default {
            if (-not [string]::IsNullOrEmpty($errorMessage)) {
                throw "Failed to create repository '$Name': HTTP $($response.StatusCode). Response: $errorMessage"
            }
            throw "Failed to create repository '$Name': HTTP $($response.StatusCode)."
        }
    }
}

function Invoke-Git {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$CaptureOutput
    )

    return Invoke-ExternalCommand -FilePath 'git' -Arguments $Arguments -CaptureOutput:$CaptureOutput
}

function Ensure-GitUserProfile {
    [CmdletBinding()]
    param()

    $profile = @{}

    $profile.Username = Get-GitConfigValue -Arguments @('config', '--global', 'user.github.login.name')
    if (-not $profile.Username) {
        $profile.Username = Read-Host 'Enter your GitHub username'
        if (-not $profile.Username) {
            throw 'GitHub username cannot be empty.'
        }
        Invoke-Git -Arguments @('config', '--global', 'user.github.login.name', $profile.Username) | Out-Null
    }

    $profile.Email = Get-GitConfigValue -Arguments @('config', '--global', 'user.email')
    if (-not $profile.Email) {
        $defaultEmail = "${($profile.Username) }@users.noreply.github.com"
        $email = Read-Host "Enter your email [$defaultEmail]"
        if (-not $email) {
            $email = $defaultEmail
        }
        Invoke-Git -Arguments @('config', '--global', 'user.email', $email) | Out-Null
        $profile.Email = $email
    }

    $profile.Name = Get-GitConfigValue -Arguments @('config', '--global', 'user.name')
    if (-not $profile.Name) {
        $profile.Name = Read-Host 'Enter your Full Name'
        if (-not $profile.Name) {
            throw 'Full name cannot be empty.'
        }
        Invoke-Git -Arguments @('config', '--global', 'user.name', $profile.Name) | Out-Null
    }

    return $profile
}

function Get-CredentialHelperValue {
    [CmdletBinding()]
    param()

    if ($IsLinux) {
        $configDir = Join-Path -Path ([Environment]::GetFolderPath('UserProfile')) -ChildPath '.config'
        if (-not (Test-Path -LiteralPath $configDir)) {
            New-Item -ItemType Directory -Path $configDir | Out-Null
        }

        $helperPath = Join-Path -Path $configDir -ChildPath 'git-credential-env'
        if (-not (Test-Path -LiteralPath $helperPath)) {
            $helperContent = @'
#!/usr/bin/env pwsh
#requires -Version 7.0
Set-StrictMode -Version Latest
$op = if ($args) { $args[0] } else { $null }
while ($true) {
    $line = [Console]::ReadLine()
    if (-not $line) { break }
}
if ($op -ne 'get') { exit 0 }
$token = $env:GITHUB_ACCESS_TOKEN
if (-not $token -and $env:GH_TOKEN_ID) {
    try {
        $secret = bws secret get $env:GH_TOKEN_ID --output json | ConvertFrom-Json -AsHashtable
        if ($secret -and $secret.value) {
            $token = [string]$secret.value
        }
    } catch {
        Write-Error "Failed to retrieve GitHub token via Bitwarden Secrets Manager: $($_.Exception.Message)"
    }
}
if (-not $token) {
    Write-Error 'Missing GitHub access token.'
    exit 1
}
Write-Output 'username=x-access-token'
Write-Output ("password={0}" -f $token)
'@
            Set-Content -LiteralPath $helperPath -Value $helperContent
            try {
                chmod +x $helperPath | Out-Null
            } catch {
                Write-Warning "Failed to mark credential helper '$helperPath' as executable: $($_.Exception.Message)"
            }
        }

        return $helperPath
    }

    if ($IsMacOS) {
        return 'osxkeychain'
    }

    if ($IsWindows) {
        return 'manager-core'
    }

    Write-Warning 'Unsupported operating system for configuring credential helpers.'
    return $null
}

function Set-GitCredentialHelper {
    [CmdletBinding()]
    param(
        [switch]$Global
    )

    $helperValue = Get-CredentialHelperValue
    if (-not $helperValue) {
        return
    }

    $arguments = @('config')
    if ($Global) {
        $arguments += '--global'
    }
    $arguments += 'credential.helper'
    $arguments += $helperValue
    Invoke-Git -Arguments $arguments | Out-Null
}

function Initialize-GitRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [hashtable]$Profile
    )

    $repoPath = Join-Path -Path (Get-Location) -ChildPath $Name
    if (Test-Path -LiteralPath $repoPath) {
        throw "Directory '$repoPath' already exists."
    }

    New-Item -ItemType Directory -Path $repoPath | Out-Null
    Push-Location -Path $repoPath
    try {
        Invoke-Git -Arguments @('init') | Out-Null

        Set-GitCredentialHelper -Global
        Invoke-Git -Arguments @('config', 'user.name', $Profile.Name) | Out-Null
        Invoke-Git -Arguments @('config', 'user.email', $Profile.Email) | Out-Null
        Invoke-Git -Arguments @('config', 'user.github.login.name', $Profile.Username) | Out-Null

        $pushDefault = Get-GitConfigValue -Arguments @('config', '--global', 'push.default')
        if (-not $pushDefault) {
            Invoke-Git -Arguments @('config', '--global', 'push.default', 'simple') | Out-Null
        }

        $remoteUrl = "https://github.com/$($Profile.Username)/$Name.git"
        Invoke-Git -Arguments @('remote', 'add', 'origin', $remoteUrl) | Out-Null

        Set-Content -LiteralPath 'README.md' -Value "$Name by $($Profile.Username)`n"
        try {
            Invoke-WebRequest -Uri 'https://www.gnu.org/licenses/gpl-3.0.txt' -OutFile 'LICENSE'
        } catch {
            Write-Warning "Failed to download GPL license text: $($_.Exception.Message)"
        }

        Invoke-Git -Arguments @('add', '.') | Out-Null
        Invoke-Git -Arguments @('commit', '-m', 'Initial commit') | Out-Null
        Invoke-Git -Arguments @('branch', '-M', 'main') | Out-Null
        Invoke-Git -Arguments @('push', '--set-upstream', 'origin', 'main') | Out-Null
    } finally {
        Pop-Location
    }
}

function Clone-GitRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryFullName
    )

    $helperValue = Get-CredentialHelperValue
    $cloneUrl = "https://github.com/$RepositoryFullName.git"

    if ($helperValue -and $IsLinux) {
        Invoke-Git -Arguments @('-c', "credential.helper=$helperValue", 'clone', $cloneUrl) | Out-Null
    } else {
        Invoke-Git -Arguments @('clone', $cloneUrl) | Out-Null
    }

    $repoName = Split-Path -Leaf $RepositoryFullName
    Push-Location -Path $repoName
    try {
        if ($helperValue) {
            Invoke-Git -Arguments @('config', 'credential.helper', $helperValue) | Out-Null
        }
        Invoke-Git -Arguments @('config', 'remote.origin.url', $cloneUrl) | Out-Null
    } finally {
        Pop-Location
    }
}

function Start-GitInit {
    [CmdletBinding()]
    param()

    $ErrorActionPreference = 'Stop'

    foreach ($command in 'bws', 'bw', 'git') {
        Ensure-CommandAvailable -Name $command
    }

    $config = Get-GitInitConfiguration
    Ensure-BWSession -Config $config | Out-Null
    $token = Get-GitHubAccessToken -Config $config
    if ($config.GH_TOKEN_ID) {
        $env:GH_TOKEN_ID = $config.GH_TOKEN_ID
    }
    $env:GITHUB_ACCESS_TOKEN = $token
    $profile = Ensure-GitUserProfile

    Write-Host ''
    Write-Host 'What would you like to do?'
    $choice = Read-MenuSelection -Options @('Create a new repository', 'Clone an existing repository')

    switch ($choice) {
        0 {
            while ($true) {
                $name = Read-Host 'Enter a unique name for the new repo'
                if (-not $name) {
                    Write-Warning 'Repository name cannot be empty.'
                    continue
                }
                try {
                    New-GitHubRepository -Name $name -Token $token
                    Initialize-GitRepository -Name $name -Profile $profile
                    break
                } catch [System.InvalidOperationException] {
                    Write-Warning $_.Exception.Message
                }
            }
        }
        1 {
            $repositories = Get-GitHubRepositories -Token $token
            if (-not $repositories -or $repositories.Count -eq 0) {
                Write-Warning 'No repositories found.'
                return
            }
            $selectedIndex = Read-MenuSelection -Options $repositories -Prompt 'Select a repository to clone'
            $selectedRepo = $repositories[$selectedIndex]
            Clone-GitRepository -RepositoryFullName $selectedRepo
        }
    }
}

if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function *-Git*, Start-GitInit, Ensure-BWSession, Get-GitHubAccessToken
}

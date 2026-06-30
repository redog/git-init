# APIKeys.psm1

# region: configuration
# Secrets Manager CLI executable (Bitwarden Secrets Manager)
$script:BwsCliPath = 'bws'

# bw item that contains your BWS access token (used to bootstrap bws)
# Store the token in either:
#   - item.notes, OR
#   - a custom field named 'token', OR
#   - the login password (falls back to .login.password)
$script:BwsTokenItem = 'Bitwarden Secrets Manager Service Account'

# Map entries:
# - Name: label for reporting/filtering
# - SecretId: Secrets Manager secret id
# - Env: hashtable of env var(s) to set
#   Values:
#     * '$secret' => replaced with retrieved secret
#     * literal   => set as-is
$script:KeyMap = @()

# Path the active config was loaded from / will be saved to. Set by
# Import-APIKeysConfig and the *-APIKeysConfig*/Add-APIKey/Remove-APIKey helpers.
$script:ConfigPath = $null

function Set-APIKeysConfig {
    <#
    .SYNOPSIS
        Sets the configuration for the API Keys module.
    .DESCRIPTION
        Allows customization of the BWS CLI path, the BWS Token item name, and the Key Map.
    .PARAMETER BwsCliPath
        Path to the Bitwarden Secrets Manager CLI executable (default: 'bws').
    .PARAMETER BwsTokenItem
        The name or ID of the item in Bitwarden that contains the BWS access token.
    .PARAMETER KeyMap
        An array of hashtables defining the mapping between secret IDs and environment variables.
    #>
    [CmdletBinding()]
    param(
        [string]$BwsCliPath,
        [string]$BwsTokenItem,
        [object[]]$KeyMap
    )

    if ($PSBoundParameters.ContainsKey('BwsCliPath')) {
        $script:BwsCliPath = $BwsCliPath
    }
    if ($PSBoundParameters.ContainsKey('BwsTokenItem')) {
        $script:BwsTokenItem = $BwsTokenItem
    }
    if ($PSBoundParameters.ContainsKey('KeyMap')) {
        $script:KeyMap = $KeyMap
    }
}

function Import-APIKeysConfig {
    <#
    .SYNOPSIS
        Imports configuration from a .json or .psd1 file.
    .DESCRIPTION
        Reads a configuration file containing keys 'BwsCliPath', 'BwsTokenItem', and 'KeyMap',
        and applies them using Set-APIKeysConfig. JSON is the canonical format (shared with
        the bash implementation); .psd1 is supported for backwards compatibility.
    .PARAMETER Path
        Path to the configuration file (.json or .psd1).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file not found (or not a file): $Path"
    }

    $config = $null
    try {
        if ($Path -match '\.json$') {
            $raw = Get-Content -Raw -LiteralPath $Path
            if ([string]::IsNullOrWhiteSpace($raw)) {
                throw "Config file is empty: $Path"
            }
            $config = $raw | ConvertFrom-Json -AsHashtable
        }
        else {
            $config = Import-PowerShellDataFile -LiteralPath $Path
        }
    }
    catch {
        throw "Failed to parse config file '$Path': $($_.Exception.Message)"
    }

    if ($null -eq $config -or -not ($config -is [System.Collections.IDictionary])) {
        throw "Config file '$Path' did not produce an object/hashtable."
    }

    # Normalize KeyMap entries so each entry's Env is a hashtable. ConvertFrom-Json
    # with -AsHashtable already gives hashtables, but keep this defensive.
    if ($config.ContainsKey('KeyMap') -and $config.KeyMap) {
        $normalized = foreach ($entry in $config.KeyMap) {
            if ($entry -is [hashtable]) { $entry }
            else {
                $h = @{}
                foreach ($p in $entry.PSObject.Properties) { $h[$p.Name] = $p.Value }
                if ($h.Env -and -not ($h.Env -is [hashtable])) {
                    $envH = @{}
                    foreach ($p in $h.Env.PSObject.Properties) { $envH[$p.Name] = $p.Value }
                    $h.Env = $envH
                }
                $h
            }
        }
        $config.KeyMap = @($normalized)
    }

    $params = @{}
    if ($config.ContainsKey('BwsCliPath'))    { $params['BwsCliPath']    = $config.BwsCliPath }
    if ($config.ContainsKey('BwsTokenItem')) { $params['BwsTokenItem'] = $config.BwsTokenItem }
    if ($config.ContainsKey('KeyMap'))       { $params['KeyMap']       = $config.KeyMap }

    Set-APIKeysConfig @params
    $script:ConfigPath = (Resolve-Path $Path).Path
}

function Get-APIKeysConfigPath {
    [CmdletBinding()]
    param()
    $script:ConfigPath
}

function Show-APIKeysConfig {
    <#
    .SYNOPSIS
        Returns the current in-memory config as a structured object.
    #>
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Path         = $script:ConfigPath
        BwsCliPath   = $script:BwsCliPath
        BwsTokenItem = $script:BwsTokenItem
        KeyMap       = $script:KeyMap
    }
}

function Save-APIKeysConfig {
    <#
    .SYNOPSIS
        Persists the in-memory config to a JSON file.
    .PARAMETER Path
        Override the destination path. Defaults to the previously loaded
        path, or ~/.git-init.json if none is set.
    #>
    [CmdletBinding()]
    param([string]$Path)

    if (-not $Path) { $Path = $script:ConfigPath }
    if (-not $Path) { $Path = Join-Path $HOME '.git-init.json' }

    $payload = [ordered]@{
        BwsCliPath   = $script:BwsCliPath
        BwsTokenItem = $script:BwsTokenItem
        KeyMap       = @($script:KeyMap)
    }

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $payload | ConvertTo-Json -Depth 10
    Set-Content -Path $Path -Value $json -Encoding utf8
    $script:ConfigPath = (Resolve-Path $Path).Path
    Write-Host "Wrote $($script:ConfigPath)"
}

function Initialize-APIKeysConfigFile {
    <#
    .SYNOPSIS
        Create a new git-init config file with empty KeyMap.
    .PARAMETER Path
        Where to write the new file. Defaults to ~/.git-init.json.
    .PARAMETER BwsTokenItem
        Name or UUID of the bw vault item holding the BWS access token.
    .PARAMETER BwsCliPath
        Path to the bws executable.
    .PARAMETER Force
        Overwrite an existing config file.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$BwsTokenItem = 'Bitwarden Secrets Manager Service Account',
        [string]$BwsCliPath = 'bws',
        [switch]$Force
    )
    if (-not $Path) { $Path = Join-Path $HOME '.git-init.json' }
    if ((Test-Path $Path) -and -not $Force) {
        Write-Warning "Config already exists at $Path. Pass -Force to overwrite, or use Add-APIKey/Set-APIKeysConfigField to modify."
        return
    }
    Set-APIKeysConfig -BwsCliPath $BwsCliPath -BwsTokenItem $BwsTokenItem -KeyMap @()
    Save-APIKeysConfig -Path $Path
}

function Add-APIKey {
    <#
    .SYNOPSIS
        Add or update a KeyMap entry and persist to the active config file.
    .PARAMETER Name
        Friendly name (e.g. "GitHub").
    .PARAMETER SecretId
        UUID of the secret in Bitwarden Secrets Manager.
    .PARAMETER Env
        Hashtable mapping env-var names to values. Use the literal '$secret'
        to inject the secret value, or any other string to set as-is.
    .PARAMETER Path
        Override save path. Defaults to the loaded path or ~/.git-init.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]    $Name,
        [Parameter(Mandatory)] [string]    $SecretId,
        [Parameter(Mandatory)] [hashtable] $Env,
        [string]                            $Path
    )
    $existing = @($script:KeyMap | Where-Object { $_.Name -ne $Name })
    $script:KeyMap = $existing + @(@{ Name = $Name; SecretId = $SecretId; Env = $Env })
    Save-APIKeysConfig -Path $Path
    Write-Host "Added/updated key '$Name'."
}

function Remove-APIKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string]                          $Path
    )
    $script:KeyMap = @($script:KeyMap | Where-Object { $_.Name -ne $Name })
    Save-APIKeysConfig -Path $Path
    Write-Host "Removed key '$Name'."
}

function Set-APIKeysConfigField {
    <#
    .SYNOPSIS
        Update a top-level config field and persist.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('BwsCliPath','BwsTokenItem')]
        [string] $Field,
        [Parameter(Mandatory)] [string] $Value,
        [string] $Path
    )
    if ($Field -eq 'BwsCliPath')   { $script:BwsCliPath   = $Value }
    if ($Field -eq 'BwsTokenItem') { $script:BwsTokenItem = $Value }
    Save-APIKeysConfig -Path $Path
    Write-Host "Set $Field = $Value"
}

# endregion

# region: verbosity
# 0=quiet  1=normal(default)  2=verbose
$script:Verbosity = 1

function Set-GitInitVerbosity {
    [CmdletBinding()]
    param([ValidateRange(0, 2)][int]$Level = 1)
    $script:Verbosity = $Level
}

function script:Write-GitInitLog {
    param([int]$Level, [string]$Message, [System.ConsoleColor]$Color = [System.ConsoleColor]::White)
    if ($script:Verbosity -ge $Level) {
        if ($Color -ne [System.ConsoleColor]::White) {
            Write-Host $Message -ForegroundColor $Color
        } else {
            Write-Host $Message
        }
    }
}
# endregion

# region: OS keychain integration
# Supported backends (auto-detected):
#   windows     - Windows Credential Manager (PasswordVault WinRT API)
#   macos       - macOS Keychain via the bundled `security` CLI
#   secret-tool - Linux GNOME Keyring / libsecret (install: app-crypt/libsecret)
#   none        - no backend; sessions will not persist across shells

function script:Get-KeychainBackend {
    if ($IsWindows)   { return 'windows' }
    if ($IsMacOS)     { return 'macos' }
    if (Get-Command secret-tool -ErrorAction SilentlyContinue) { return 'secret-tool' }
    return 'none'
}

function Save-GitInitCredential {
    <#
    .SYNOPSIS
        Saves a credential to the OS keychain under the git-init service.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Key,
        [Parameter(Mandatory)] [string] $Value
    )
    $svc = 'git-init'
    switch (Get-KeychainBackend) {
        'windows' {
            [void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
            $vault = New-Object Windows.Security.Credentials.PasswordVault
            try { $vault.Remove($vault.Retrieve($svc, $Key)) } catch {}
            $vault.Add((New-Object Windows.Security.Credentials.PasswordCredential($svc, $Key, $Value)))
        }
        'macos' {
            & security add-generic-password -s $svc -a $Key -w $Value -U 2>$null
        }
        'secret-tool' {
            $Value | & secret-tool store --label="git-init: $Key" service $svc account $Key 2>$null
        }
        'none' {
            if ($VerbosePreference -ne 'SilentlyContinue') {
                Write-Warning "No keychain backend available. Install libsecret (provides secret-tool) on Linux to persist sessions across shells."
            }
        }
    }
}

function Get-GitInitCredential {
    <#
    .SYNOPSIS
        Retrieves a credential from the OS keychain under the git-init service.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Key
    )
    $svc = 'git-init'
    switch (Get-KeychainBackend) {
        'windows' {
            try {
                [void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
                $vault = New-Object Windows.Security.Credentials.PasswordVault
                $c = $vault.Retrieve($svc, $Key)
                $c.RetrievePassword()
                return $c.Password
            } catch { return $null }
        }
        'macos' {
            $out = & security find-generic-password -s $svc -a $Key -w 2>$null
            if ($LASTEXITCODE -eq 0) { return $out } else { return $null }
        }
        'secret-tool' {
            $out = & secret-tool lookup service $svc account $Key 2>$null
            if ($LASTEXITCODE -eq 0) { return $out } else { return $null }
        }
        'none' { return $null }
    }
}

function Remove-GitInitCredential {
    <#
    .SYNOPSIS
        Removes a credential from the OS keychain under the git-init service.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Key
    )
    $svc = 'git-init'
    switch (Get-KeychainBackend) {
        'windows' {
            try {
                [void][Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
                $vault = New-Object Windows.Security.Credentials.PasswordVault
                $vault.Remove($vault.Retrieve($svc, $Key))
            } catch {}
        }
        'macos' {
            & security delete-generic-password -s $svc -a $Key 2>$null | Out-Null
        }
        'secret-tool' {
            & secret-tool clear service $svc account $Key 2>$null
        }
        'none' {}
    }
}

function Save-GitInitSession {
    <#
    .SYNOPSIS
        Saves BW_SESSION and BWS_ACCESS_TOKEN to the OS keychain.
    #>
    [CmdletBinding()]
    param()
    if ($env:BW_SESSION) {
        Save-GitInitCredential -Key 'bw_session' -Value $env:BW_SESSION
        Write-Host "BW session saved to keychain." -ForegroundColor DarkGray
    }
    if ($env:BWS_ACCESS_TOKEN) {
        Save-GitInitCredential -Key 'bws_token' -Value $env:BWS_ACCESS_TOKEN
        Write-Host "BWS token saved to keychain." -ForegroundColor DarkGray
    }
}

function Restore-GitInitSession {
    <#
    .SYNOPSIS
        Restores BW_SESSION and BWS_ACCESS_TOKEN from the OS keychain into the current environment.
    #>
    [CmdletBinding()]
    param()
    $val = Get-GitInitCredential -Key 'bw_session'
    if (-not [string]::IsNullOrWhiteSpace($val)) { $env:BW_SESSION = $val }
    $val = Get-GitInitCredential -Key 'bws_token'
    if (-not [string]::IsNullOrWhiteSpace($val)) { $env:BWS_ACCESS_TOKEN = $val }
}

function Clear-GitInitSession {
    <#
    .SYNOPSIS
        Removes all git-init credentials from the OS keychain and unsets them in the environment.
    .DESCRIPTION
        Clears BW_SESSION, BWS_ACCESS_TOKEN, and every cached secret value (keyed by SecretId).
        Call this after a token rotation or to force a full re-authentication on the next run.
    #>
    [CmdletBinding()]
    param()
    Remove-GitInitCredential -Key 'bw_session'
    Remove-GitInitCredential -Key 'bws_token'
    Remove-Item -Path Env:BW_SESSION       -ErrorAction SilentlyContinue
    Remove-Item -Path Env:BWS_ACCESS_TOKEN -ErrorAction SilentlyContinue

    # Clear cached secret values keyed by each entry's SecretId.
    foreach ($entry in $script:KeyMap) {
        $secretId = $entry.SecretId
        if (-not [string]::IsNullOrWhiteSpace($secretId)) {
            Remove-GitInitCredential -Key "secret:$secretId"
        }
    }

    Write-Host "Session cleared from keychain." -ForegroundColor DarkGray
}

# endregion

# region: bitwarden bootstrap
function Connect-Bitwarden {
    <#
    .SYNOPSIS
        Ensures the Bitwarden CLI is logged in and unlocked.
    .DESCRIPTION
        Checks 'bw status'.
        - Restores a saved BW session from the OS keychain before checking status.
        - If unauthenticated: purges stale keychain entries, then logs in via API key
          or interactive prompt, and saves the new session to the keychain.
        - If locked: purges stale keychain entries, unlocks interactively, and saves
          the new session to the keychain.
    #>
    [CmdletBinding()]
    param(
        [switch]$NoCache
    )

    if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
        throw "Bitwarden CLI 'bw' not found in PATH."
    }

    # Restore a previously saved BW session from the OS keychain unless NoCache is specified.
    if (-not $env:BW_SESSION -and -not $NoCache) {
        $cached = Get-GitInitCredential -Key 'bw_session'
        if (-not [string]::IsNullOrWhiteSpace($cached)) {
            $env:BW_SESSION = $cached
        }
    }

    $status = bw status | ConvertFrom-Json

    if ($status.status -eq 'unauthenticated') {
        Write-Verbose "Bitwarden is unauthenticated — clearing stale keychain entries."
        Remove-GitInitCredential -Key 'bw_session'
        Remove-GitInitCredential -Key 'bws_token'
        Remove-Item -Path Env:BW_SESSION       -ErrorAction SilentlyContinue
        Remove-Item -Path Env:BWS_ACCESS_TOKEN -ErrorAction SilentlyContinue

        if ($env:BW_CLIENTID -and $env:BW_CLIENTSECRET) {
            Write-GitInitLog -Level 1 -Message "🤖 Logging in with API Key..." -Color Cyan
            $session = bw login --apikey --raw
            if ($LASTEXITCODE -ne 0) { throw "API Key login failed." }
        }
        else {
            Write-GitInitLog -Level 1 -Message "👤 Logging in interactively..." -Color Cyan
            $session = bw login --raw
            if ($LASTEXITCODE -ne 0) { throw "Interactive login failed." }
        }

        if (-not [string]::IsNullOrWhiteSpace($session)) {
            $env:BW_SESSION = $session.Trim()
            Save-GitInitCredential -Key 'bw_session' -Value $env:BW_SESSION
            Write-GitInitLog -Level 2 -Message "BW session saved to keychain." -Color DarkGray
        }

        $status = bw status | ConvertFrom-Json
    }

    if ($status.status -eq 'locked') {
        # Vault locked — any cached session has expired; clear it and unlock.
        Remove-GitInitCredential -Key 'bw_session'
        Remove-GitInitCredential -Key 'bws_token'
        Remove-Item -Path Env:BW_SESSION       -ErrorAction SilentlyContinue
        Remove-Item -Path Env:BWS_ACCESS_TOKEN -ErrorAction SilentlyContinue

        Write-GitInitLog -Level 1 -Message "🔓 Unlocking Vault..." -Color Cyan
        $session = bw unlock --raw
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($session)) {
            throw "Failed to unlock bw vault (could not obtain session key)."
        }
        $env:BW_SESSION = $session.Trim()
        Save-GitInitCredential -Key 'bw_session' -Value $env:BW_SESSION
        Write-GitInitLog -Level 2 -Message "BW session saved to keychain." -Color DarkGray
        Write-GitInitLog -Level 1 -Message "✅ Vault unlocked." -Color Green
    }
}

function Get-BwsAccessToken {
    [CmdletBinding()]
    param(
        [string]$BwsTokenItemIdOrName = $script:BwsTokenItem,
        [switch]$NoCache
    )

    # Opportunistically restore BW_SESSION from the OS keychain if not set,
    # so the user can use the 'bw' CLI tool even if we only need the 'bws' token.
    if (-not $env:BW_SESSION -and -not $NoCache) {
        $cachedSession = Get-GitInitCredential -Key 'bw_session'
        if (-not [string]::IsNullOrWhiteSpace($cachedSession)) {
            $env:BW_SESSION = $cachedSession
        }
    }

    $forceUnlock = (-not $env:BW_SESSION -and $NoCache)

    if (-not $env:BWS_ACCESS_TOKEN) {
        # Try the OS keychain for a previously saved BWS token (avoids BW unlock).
        if (-not $NoCache) {
            $cached = Get-GitInitCredential -Key 'bws_token'
            if (-not [string]::IsNullOrWhiteSpace($cached)) {
                $env:BWS_ACCESS_TOKEN = $cached
            }
        }
    }

    if (-not $env:BWS_ACCESS_TOKEN -or $forceUnlock) {
        Connect-Bitwarden -NoCache:$NoCache
    }

    if (-not $env:BWS_ACCESS_TOKEN) {
        $item = bw get item $BwsTokenItemIdOrName | ConvertFrom-Json

        $token = $null
        if (-not [string]::IsNullOrWhiteSpace($item.notes)) {
            $token = $item.notes
        }
        if (-not $token -and $item.fields) {
            $token = ($item.fields | Where-Object name -eq 'token' | Select-Object -ExpandProperty value -First 1)
        }
        if (-not $token -and $item.login -and -not [string]::IsNullOrWhiteSpace($item.login.password)) {
            $token = $item.login.password
        }

        if ([string]::IsNullOrWhiteSpace($token)) {
            throw "Could not extract BWS access token from bw item '$BwsTokenItemIdOrName'. Store it in notes, a custom field named 'token', or the login password."
        }

        $env:BWS_ACCESS_TOKEN = $token.Trim()
        Save-GitInitCredential -Key 'bws_token' -Value $env:BWS_ACCESS_TOKEN
        Write-GitInitLog -Level 2 -Message "BWS token saved to keychain." -Color DarkGray
    }

    if (-not (Get-Command $script:BwsCliPath -ErrorAction SilentlyContinue)) {
        throw "Bitwarden Secrets Manager CLI '$script:BwsCliPath' not found in PATH. Install 'bws' or adjust `$script:BwsCliPath."
    }
}
# endregion

# region: secrets manager access
function Get-BwsSecretValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SecretId
    )

    try {
        Write-Verbose "Executing: $script:BwsCliPath secret get $SecretId -o tsv"
        $out = & $script:BwsCliPath secret get $SecretId -o tsv

        if ($null -eq $out -or $out.Count -eq 0) {
            Write-Warning "No output received from bws for secret ID $SecretId."
            return $null
        }

        # last line, tab-separated, value in field 3 (index 2)
        $value = ($out | Select-Object -Last 1).Split("`t")[2]
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }

        return $value
    }
    catch {
        Write-Error "Failed to retrieve secret with ID $SecretId. Error: $_"
        return $null
    }
}

function Set-APIKeysFromMapEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry,
        [switch]$Quiet,
        [switch]$NoCache
    )

    $name     = $Entry.Name
    $secretId = $Entry.SecretId
    $envMap   = $Entry.Env

    Write-Verbose "Loading $name..."

    # Try OS keychain first; fall back to BWS on a miss or -NoCache.
    $secret = $null
    if (-not $NoCache) {
        $cached = Get-GitInitCredential -Key "secret:$secretId"
        if (-not [string]::IsNullOrWhiteSpace($cached)) { $secret = $cached }
    }

    if (-not $secret) {
        $secret = Get-BwsSecretValue -SecretId $secretId -Verbose:$VerbosePreference
        if (-not $secret) {
            Write-Warning "Could not load $name (SecretId: $secretId)."
            return $false
        }
        Save-GitInitCredential -Key "secret:$secretId" -Value $secret
        Write-GitInitLog -Level 2 -Message "$name cached in keychain." -Color DarkGray
    }

    foreach ($kv in $envMap.GetEnumerator()) {
        $envName = $kv.Key
        $value   = $kv.Value

        if ($value -is [string] -and $value -eq '$secret') {
            $value = $secret
        }

        Set-Item -Path "Env:$envName" -Value $value
        Write-Verbose "$envName set."
    }

    if (-not $Quiet) { Write-GitInitLog -Level 2 -Message "$name loaded." }
    return $true
}

function Get-APIKeyMap {
    [CmdletBinding()]
    param()
    $script:KeyMap
}

function Set-AllAPIKeys {
    [CmdletBinding()]
    param(
        # Filter by Name OR by env var name
        [string[]]$Only,
        [string[]]$Except,
        [switch]$Quiet,
        [switch]$NoCache
    )

    # Bootstrap bws token from bw (prompts if bw is locked)
    Get-BwsAccessToken -NoCache:$NoCache

    $entries = $script:KeyMap

    if ($null -eq $entries -or $entries.Count -eq 0) {
        Write-Warning "KeyMap is empty. Please configure the module using Set-APIKeysConfig or Import-APIKeysConfig."
        return [pscustomobject]@{ Success = 0; Failed = 0; Total = 0 }
    }

    if ($Only) {
        $onlySet = [System.Collections.Generic.HashSet[string]]::new([string[]]$Only, [System.StringComparer]::OrdinalIgnoreCase)
        $entries = $entries | Where-Object {
            $onlySet.Contains($_.Name) -or ($_.Env.Keys | Where-Object { $onlySet.Contains($_) })
        }
    }

    if ($Except) {
        $exceptSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$Except, [System.StringComparer]::OrdinalIgnoreCase)
        $entries = $entries | Where-Object {
            -not ($exceptSet.Contains($_.Name) -or ($_.Env.Keys | Where-Object { $exceptSet.Contains($_) }))
        }
    }

    $ok = 0
    $fail = 0

    foreach ($e in $entries) {
        if (Set-APIKeysFromMapEntry -Entry $e -Quiet:$Quiet -NoCache:$NoCache -Verbose:$VerbosePreference) { $ok++ } else { $fail++ }
    }

    if (-not $Quiet) {
        Write-GitInitLog -Level 1 -Message "API keys loaded. Success: $ok  Failed: $fail"
    }

    [pscustomobject]@{ Success = $ok; Failed = $fail; Total = $ok + $fail }
}

function Clear-APIKeyEnv {
    [CmdletBinding()]
    param(
        # Also remove BW_SESSION and BWS_ACCESS_TOKEN
        [switch]$ClearBitwardenSession
    )

    foreach ($entry in $script:KeyMap) {
        foreach ($k in $entry.Env.Keys) {
            Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue
        }
    }

    if ($ClearBitwardenSession) {
        Clear-GitInitSession
    }
}
# endregion

Set-Alias -Name load_keys -Value Set-AllAPIKeys
Export-ModuleMember -Function `
    Get-BwsSecretValue, Get-APIKeyMap, Set-AllAPIKeys, Clear-APIKeyEnv, `
    Set-APIKeysConfig, Import-APIKeysConfig, Connect-Bitwarden, `
    Show-APIKeysConfig, Save-APIKeysConfig, Get-APIKeysConfigPath, `
    Initialize-APIKeysConfigFile, Add-APIKey, Remove-APIKey, Set-APIKeysConfigField, `
    Save-GitInitCredential, Get-GitInitCredential, Remove-GitInitCredential, `
    Save-GitInitSession, Restore-GitInitSession, Clear-GitInitSession, `
    Set-GitInitVerbosity, Write-GitInitLog `
    -Alias load_keys

# ApiKeys.psm1

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

function Set-ApiKeysConfig {
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

function Import-ApiKeysConfig {
    <#
    .SYNOPSIS
        Imports configuration from a .psd1 file.
    .DESCRIPTION
        Reads a PowerShell data file (.psd1) containing a hashtable with keys 'BwsCliPath', 'BwsTokenItem', and 'KeyMap',
        and applies them using Set-ApiKeysConfig.
    .PARAMETER Path
        Path to the .psd1 configuration file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Configuration file not found: $Path"
    }

    $config = Import-PowerShellDataFile -Path $Path

    $params = @{}
    if ($config.ContainsKey('BwsCliPath')) { $params['BwsCliPath'] = $config.BwsCliPath }
    if ($config.ContainsKey('BwsTokenItem')) { $params['BwsTokenItem'] = $config.BwsTokenItem }
    if ($config.ContainsKey('KeyMap')) { $params['KeyMap'] = $config.KeyMap }

    Set-ApiKeysConfig @params
}

# endregion

# region: bitwarden bootstrap
function Get-BwSessionEnv {
    [CmdletBinding()]
    param()

    if (-not (Get-Command bw -ErrorAction SilentlyContinue)) {
        throw "Bitwarden CLI 'bw' not found in PATH. Install it or ensure it's available."
    }

    $status = bw status | ConvertFrom-Json

    if ($status.status -eq 'unauthenticated') {
        throw "bw is unauthenticated. Run: bw login"
    }

    if ($status.status -eq 'locked') {
        # This will prompt for your master password if needed.
        $session = bw unlock --raw
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($session)) {
            throw "Failed to unlock bw vault (could not obtain session key)."
        }
        $env:BW_SESSION = $session.Trim()

        # sanity check
        $status2 = bw status | ConvertFrom-Json
        if ($status2.status -ne 'unlocked') {
            throw "bw did not report unlocked after setting BW_SESSION (status: $($status2.status))."
        }
    }
}

function Get-BwsAccessToken {
    [CmdletBinding()]
    param(
        [string]$BwsTokenItemIdOrName = $script:BwsTokenItem
    )

    if (-not $env:BWS_ACCESS_TOKEN) {
        Get-BwSessionEnv
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

function Set-ApiKeysFromMapEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Entry,
        [switch]$Quiet
    )

    $name     = $Entry.Name
    $secretId = $Entry.SecretId
    $envMap   = $Entry.Env

    Write-Verbose "Loading $name..."

    $secret = Get-BwsSecretValue -SecretId $secretId -Verbose:$VerbosePreference
    if (-not $secret) {
        Write-Warning "Could not load $name (SecretId: $secretId)."
        return $false
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

    if (-not $Quiet) { Write-Host "$name loaded." }
    return $true
}

function Get-ApiKeyMap {
    [CmdletBinding()]
    param()
    $script:KeyMap
}

function Set-AllApiKeys {
    [CmdletBinding()]
    param(
        # Filter by Name OR by env var name
        [string[]]$Only,
        [string[]]$Except,
        [switch]$Quiet
    )

    # Bootstrap bws token from bw (prompts if bw is locked)
    Get-BwsAccessToken

    $entries = $script:KeyMap

    if ($null -eq $entries -or $entries.Count -eq 0) {
        Write-Warning "KeyMap is empty. Please configure the module using Set-ApiKeysConfig or Import-ApiKeysConfig."
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
        if (Set-ApiKeysFromMapEntry -Entry $e -Quiet:$Quiet -Verbose:$VerbosePreference) { $ok++ } else { $fail++ }
    }

    if (-not $Quiet) {
        Write-Host "API keys loaded. Success: $ok  Failed: $fail"
    }

    [pscustomobject]@{ Success = $ok; Failed = $fail; Total = $ok + $fail }
}

function Clear-ApiKeyEnv {
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
        Remove-Item -Path Env:BW_SESSION -ErrorAction SilentlyContinue
        Remove-Item -Path Env:BWS_ACCESS_TOKEN -ErrorAction SilentlyContinue
    }
}
# endregion

Set-Alias -Name load_keys -Value Set-AllApiKeys
Export-ModuleMember -Function Get-BwsSecretValue, Get-ApiKeyMap, Set-AllApiKeys, Clear-ApiKeyEnv, Set-ApiKeysConfig, Import-ApiKeysConfig -Alias load_keys

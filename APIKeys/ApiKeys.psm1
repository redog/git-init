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
$script:KeyMap = @(
    @{ Name='Mistral'    ; SecretId='f9e077a8-86e0-43d8-8fe0-b2b500f258ea' ; Env=@{ MISTRAL_API_KEY      = '$secret' } }
    @{ Name='Claude'     ; SecretId='3d9cd15a-fb36-4c99-90be-b2a8010f4709' ; Env=@{ CLAUDE_API_KEY       = '$secret' } }
    @{ Name='Gemini'     ; SecretId='6f8bdc68-6802-474f-bde5-b1690043038f' ; Env=@{ GEMINI_API_KEY       = '$secret' } }
    @{ Name='Groq'       ; SecretId='437f8d17-a314-46db-b043-b18e0110bde1' ; Env=@{ GROQ_API_KEY         = '$secret' } }
    @{ Name='Tavily'     ; SecretId='c8b5ce6a-5b35-403f-ad86-b2c70149f052' ; Env=@{ TAVILY_API_KEY       = '$secret' } }

    # LangSmith: one secret -> multiple env vars + tracing flag
    @{ Name='LangSmith'  ; SecretId='ad3f662b-9c78-4d22-9e15-b2c70147eabc' ; Env=@{
        LANGCHAIN_TRACING_V2 = 'true'
        LANGCHAIN_API_KEY    = '$secret'
        LANGSMITH_API_KEY    = '$secret'
    } }

    @{ Name='Notion'     ; SecretId='7909c25f-f3d3-44ea-8b86-aff8010d5ce9' ; Env=@{ NOTION_API_TOKEN     = '$secret' } }
    @{ Name='OpenAI'     ; SecretId='fbe0690e-fb43-4e91-b49c-b0b50039847a' ; Env=@{ OPENAI_API_KEY       = '$secret' } }
    @{ Name='GitHub'     ; SecretId='857d0c2c-cfe0-4e6d-995c-b1690020f8fb' ; Env=@{ GITHUB_ACCESS_TOKEN  = '$secret' } }
    @{ Name='Cloudflare' ; SecretId='c912c706-c8a3-4928-afa3-b064003857f6' ; Env=@{ CF_ACCESS_TOKEN      = '$secret' } }
    @{ Name='Fernet'     ; SecretId='d16db1df-6bcf-4f90-a341-b0640187c855' ; Env=@{ FN_ENC_KEY           = '$secret' } }
    @{ Name='Vault'      ; SecretId='42e1e10a-8ea9-427c-9c9e-b070013edb70' ; Env=@{ VAULT_PASSWORD       = '$secret' } }
)
# endregion

# region: bitwarden bootstrap
function Ensure-BwSession {
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

function Ensure-BwsAccessToken {
    [CmdletBinding()]
    param(
        [string]$BwsTokenItemIdOrName = $script:BwsTokenItem
    )

    if (-not $env:BWS_ACCESS_TOKEN) {
        Ensure-BwSession

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
    Ensure-BwsAccessToken

    $entries = $script:KeyMap

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

Export-ModuleMember -Function Get-BwsSecretValue, Get-ApiKeyMap, Set-AllApiKeys, Clear-ApiKeyEnv -Alias load_keys

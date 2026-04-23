# KeyRotation.psm1
# Extension for APIKeys to handle updating secrets in Bitwarden Secrets Manager

#Requires -Version 7.0
Set-StrictMode -Version Latest

function Update-VaultAPIKey {
    <#
    .SYNOPSIS
        Updates an API key in Bitwarden Secrets Manager and reloads it into the current session.
    .DESCRIPTION
        Takes an API key mapped in your config.psd1, updates its value in BWS using the CLI,
        and then calls Set-AllAPIKeys to update your current environment variables.
    .PARAMETER Name
        The friendly name of the key as defined in your KeyMap (e.g., 'GitHub', 'OpenAI').
    .PARAMETER NewValue
        The new API key/secret string.
    .EXAMPLE
        Update-VaultAPIKey -Name "GitHub" -NewValue "github_pat_11111111..."
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [Parameter(Mandatory=$false)]
        [string]$NewValue
    )

    if ([string]::IsNullOrWhiteSpace($NewValue)) {
        $secureInput = Read-Host "Enter the new API key for $Name" -AsSecureString
        # Convert the securely read string back to plain text for the BWS CLI payload
        $NewValue = ConvertFrom-SecureString -SecureString $secureInput -AsPlainText
    }

    # 1. Verify APIKeys module is loaded and get the KeyMap
    if (-not (Get-Command Get-APIKeyMap -ErrorAction SilentlyContinue)) {
        throw "The APIKeys module is not loaded. Please import it first."
    }

    $keyMap = Get-APIKeyMap
    $entry = $keyMap | Where-Object { $_.Name -eq $Name }

    if (-not $entry) {
        throw "Could not find a key mapped to '$Name' in the configuration. Check your config.psd1."
    }

    $secretId = $entry.SecretId

    Write-Host "Updating secret '$Name' ($secretId) in Bitwarden Secrets Manager..." -ForegroundColor Cyan

    # 2. Ensure we have the BWS Access token
    # Get-BwsAccessToken is an internal function in APIKeys, but Connect-Bitwarden is exported.
    # We can trigger a quick load to ensure auth is active.
    Connect-Bitwarden

    # 3. Use BWS CLI to edit the secret
    try {
        # The BWS CLI secret edit command updates the value
        $editOutput = & bws secret edit $secretId --value $NewValue -o json | ConvertFrom-Json
        
        if ($null -eq $editOutput -or $editOutput.id -ne $secretId) {
            throw "Unexpected output from bws CLI."
        }
        Write-Host "✅ Vault updated successfully for '$Name'." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to update secret in BWS. Error: $_"
        return
    }

    # 4. Reload the specific key into the current session
    Write-Host "🔄 Reloading '$Name' into current environment..." -ForegroundColor Cyan
    Set-AllAPIKeys -Only $Name -Quiet

    Write-Host "🚀 Done! Your terminal is using the new key." -ForegroundColor Green
}

function Invoke-AutomatedKeyRotation {
    <#
    .SYNOPSIS
        Example template for fully automating a key rotation.
    .DESCRIPTION
        If a service (unlike GitHub) allows you to use your old key to generate a new one,
        you can use this template to fully automate the rotation lifecycle.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    Write-Host "Starting automated rotation for $Name..."

    # Example generic logic:
    # 1. Grab current key from env
    # $currentKey = $env:MY_SERVICE_API_KEY
    
    # 2. Call the provider's API to generate a new key
    # $response = Invoke-RestMethod -Uri "https://api.example.com/v1/keys/rotate" -Headers @{ Authorization = "Bearer $currentKey" } -Method Post
    # $newKey = $response.new_api_key

    # 3. Save it to BWS using our new tool
    # Update-VaultAPIKey -Name $Name -NewValue $newKey

    Write-Host "Feature template. Implement the API call for your specific service here!" -ForegroundColor Yellow
}

Export-ModuleMember -Function Update-VaultAPIKey, Invoke-AutomatedKeyRotation

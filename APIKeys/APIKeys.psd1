@{
    RootModule        = 'APIKeys.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = '00000000-0000-0000-0000-000000000000'
    Author            = 'Eric Ortego'
    Description       = 'Loads API keys from Bitwarden Secrets Manager into environment variables.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Get-BwsSecretValue','Get-APIKeyMap','Set-AllAPIKeys','Clear-APIKeyEnv',
        'Set-APIKeysConfig','Import-APIKeysConfig','Connect-Bitwarden',
        'Show-APIKeysConfig','Save-APIKeysConfig','Get-APIKeysConfigPath',
        'Initialize-APIKeysConfigFile','Add-APIKey','Remove-APIKey','Set-APIKeysConfigField',
        'Save-GitInitCredential','Get-GitInitCredential','Remove-GitInitCredential',
        'Save-GitInitSession','Restore-GitInitSession','Clear-GitInitSession',
        'Save-GitInitMasterPassword','Remove-GitInitMasterPassword','Test-GitInitMasterPassword',
        'Set-GitInitVerbosity','Write-GitInitLog'
    )
    AliasesToExport   = @('load_keys')
}

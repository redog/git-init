@{
    RootModule        = 'ApiKeys.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '00000000-0000-0000-0000-000000000000'
    Author            = 'Eric Ortego'
    Description       = 'Loads API keys from Bitwarden Secrets Manager into environment variables.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Get-BwsSecretValue','Get-ApiKeyMap','Set-AllApiKeys')
    AliasesToExport   = @('load_keys')
}

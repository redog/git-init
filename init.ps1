#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path -Path $scriptRoot -ChildPath 'GitInit.psm1')

try {
    Start-GitInit
} catch {
    Write-Error $_
    exit 1
}

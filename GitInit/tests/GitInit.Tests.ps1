# Pester tests for GitInit module

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir/../GitInit.psm1"

Describe "Core Functions" {
    BeforeEach {
        # Mock external commands to avoid actual calls
        Mock -CommandName 'bw' -MockWith { return '{"status":"unlocked"}' | ConvertFrom-Json }
        Mock -CommandName 'bws' -MockWith { return '{"value":"mock_secret"}' | ConvertFrom-Json }
        Mock -CommandName 'git' -MockWith { }
        Mock -CommandName 'Invoke-RestMethod' -MockWith { return @{ full_name = "test/repo" } }
        Mock -CommandName 'Invoke-WebRequest' -MockWith { }
    }

    It "Ensure-BWSession should handle unlocked vault" {
        Mock -CommandName 'bw' -MockWith { return '{"status":"unlocked"}' | ConvertFrom-Json }
        { Ensure-BWSession } | Should -Not -Throw
    }

    It "Ensure-BWSession should handle locked vault" {
        Mock -CommandName 'bw' -MockWith {
            if ($bw_status_call_count -eq 0) {
                $script:bw_status_call_count = 1
                return '{"status":"locked"}' | ConvertFrom-Json
            }
            return '{"status":"unlocked"}' | ConvertFrom-Json
        }
        { Ensure-BWSession } | Should -Not -Throw
    }

    It "Get-SecretValue should return a secret" {
        $secret = Get-SecretValue -SecretId "some-id"
        $secret | Should -Be "mock_secret"
    }

    It "Get-GHRepositories should return repositories" {
        $repos = Get-GHRepositories -Token "some-token"
        $repos | Should -Be "test/repo"
    }

    It "New-GHRepository should create a repository" {
        $repo = New-GHRepository -RepoName "new-repo" -Token "some-token"
        $repo.full_name | Should -Be "test/repo"
    }

    It "Initialize-LocalGitRepository should initialize a repo" {
        Mock -CommandName 'New-Item' -MockWith {}
        Mock -CommandName 'Set-Location' -MockWith {}
        Mock -CommandName 'Out-File' -MockWith {}
        { Initialize-LocalGitRepository -RepoName "new-repo" -Username "testuser" } | Should -Not -Throw
    }

    It "Set-GitCredentialHelper should configure for Windows" {
        $global:isWindows = $true
        $global:isMac = $false
        $global:isLinux = $false
        { Set-GitCredentialHelper } | Should -Not -Throw
    }
}
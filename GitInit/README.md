# GitInit Module

The **GitInit** module provides PowerShell functions for interacting with GitHub and initializing local Git repositories. It is a core component of the Git-Init tool but can also be imported and used independently.

## Features

- **GitHub API Integration:** Create private repositories and list existing repositories.
- **Local Git Setup:** Initialize a repository, set up remote origin, create README/LICENSE, and push the initial commit.
- **User Info Retrieval:** Fetch authenticated user details from GitHub.

## Usage

While primarily used by the root `init.ps1` script, you can import this module to use its functions directly.

```powershell
Import-Module ./GitInit/GitInit.psm1
```

*Note: The module requires the `GITHUB_ACCESS_TOKEN` environment variable to be set (typically handled by the `APIKeys` module).*

## Functions

### `New-GHRepository`

Creates a new private repository on GitHub.

**Parameters:**
- `-RepoName`: The name of the repository to create.

```powershell
New-GHRepository -RepoName "MyNewProject"
```

### `Get-GHRepositories`

Fetches a list of all repositories for the authenticated user.

```powershell
$repos = Get-GHRepositories
```

### `Initialize-LocalGitRepository`

Initializes a local directory as a Git repository, configures user details, and pushes to GitHub.

**Parameters:**
- `-RepoName`: Name of the directory/repo.
- `-Username`: GitHub username.
- `-Name`: User's full name (for git config).
- `-Email`: User's email (for git config).

```powershell
Initialize-LocalGitRepository -RepoName "MyNewProject" -Username "octocat" -Name "The Octocat" -Email "octocat@github.com"
```

### `Get-GHUser`

Retrieves the login username of the authenticated GitHub user.

```powershell
$user = Get-GHUser
Write-Host "Logged in as $user"
```

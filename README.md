# Git-Init (PowerShell)

A cross-platform PowerShell tool to streamline the initialization and cloning of GitHub repositories, with integrated secret management using Bitwarden.

## Overview

This tool automates the process of:
1.  **Authentication:** Securely loading API keys (like your GitHub Token) from Bitwarden Secrets Manager.
2.  **Creation:** Creating new private repositories on GitHub via the API.
3.  **Initialization:** Setting up local Git repositories with proper remotes, license, and initial commit.
4.  **Cloning:** Cloning existing repositories with automatic credential helper configuration.

It replaces the legacy shell scripts (`init.sh`, `mkrepo.sh`) with a robust PowerShell implementation suitable for Windows, macOS, and Linux.

## Prerequisites

1.  **PowerShell 7+** (`pwsh`)
2.  **Git**
3.  **Bitwarden CLI** (`bw`) - For vault unlocking.
4.  **Bitwarden Secrets Manager CLI** (`bws`) - For secret retrieval.

### Installing Prerequisites (Windows)

```powershell
winget install pwsh
winget install Git.Git
winget install Bitwarden.CLI
```

For `bws`, you can use the included helper script:
```powershell
./MInstall-BWS.ps1
```

## Setup

### 1. Configuration

Create a configuration file to tell the tool which secrets to load. You can place this file at `./config.psd1` (in the repo root) or `~/.git-init.ps1`.

**Example `config.psd1`:**

```powershell
@{
    # Optional: Path to bws executable if not in PATH
    # BwsCliPath = 'bws'

    # The item in your vault containing the BWS Access Token
    BwsTokenItem = 'Bitwarden Secrets Manager Service Account'

    # Map secrets to environment variables
    KeyMap = @(
        @{
            Name     = 'GitHub'
            SecretId = 'your-secret-uuid-here'
            Env      = @{ GITHUB_ACCESS_TOKEN = '$secret' }
        }
    )
}
```

*Note: You must have a secret in Bitwarden Secrets Manager containing your GitHub Personal Access Token, and map it to `GITHUB_ACCESS_TOKEN`.*

### 2. Bitwarden Login

Ensure you are logged into the Bitwarden CLI:

```powershell
bw login
```

## Usage

Run the main entry point script:

```powershell
./init.ps1
```

The script will:
1.  Unlock your Bitwarden vault (prompting for master password/PIN if needed) to retrieve the BWS Access Token.
2.  Use `bws` to fetch your GitHub Token and inject it into the process.
3.  Present a menu to **Create** or **Clone** a repository.

### Creating a Repository
- Prompts for repo name.
- Creates a private repo on GitHub.
- Initializes the local folder, adds remote, creates README/LICENSE, and pushes.

### Cloning a Repository
- Fetches your repo list from GitHub.
- interactive selection.
- Clones the repo.

## Architecture

- **`init.ps1`**: Main orchestration script. Handles user interaction.
- **`APIKeys/`**: Module for Bitwarden integration and secret loading.
- **`GitInit/`**: Module for GitHub API interaction and local Git commands.

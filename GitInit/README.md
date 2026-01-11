# GitInit (PowerShell Port)

This project is a PowerShell port of the GitInit shell scripts. Its primary intent is to provide a cross-platform, idiomatic PowerShell solution for initializing and managing Git repositories with integrated Bitwarden secret management.

It streamlines the process of:
1.  Authenticating with Bitwarden.
2.  Retrieving GitHub tokens securely.
3.  Creating new private repositories on GitHub.
4.  Cloning existing repositories.
5.  Configuring local Git credentials.

## Prerequisites

Ensure you have the following installed and available in your PATH:

*   **PowerShell** (pwsh)
*   **Git**
*   **Bitwarden CLI** (`bw`)
*       winget install Bitwarden.CLI
*   **Bitwarden Secrets Manager** (`bws`)
*       winget install Microsoft.VCRedist.2015+.x64
*       ./MInstall-BWS.ps1

## Getting Started

### 1. Configuration

The script relies on a configuration file to locate your secrets. Create a file named `config.psd1` in the `GitInit` directory, or `.git-init.ps1` in your home directory (`~/.git-init.ps1`).

The file should contain a hashtable with your environment variables. At a minimum, you need the `GH_TOKEN_ID` (the ID of the secret in Bitwarden Secrets Manager containing your GitHub Personal Access Token).

**Example `config.psd1`:**

```powershell
@{
    # Required: Bitwarden Secrets Manager ID for your GitHub Token
    GH_TOKEN_ID = "your-secret-uuid-here"

    # Optional: Bitwarden API credentials for automated login
    # BW_CLIENTID = "client_id_..."
    # BW_CLIENTSECRET = "client_secret_..."
}
```

To obtain the `GH_TOKEN_ID`, check the main repository README or use `bws secret list`.

### 2. Usage

Run the entry point script from a PowerShell session:

```powershell
./GitInit/init.ps1
```

The script will:
1.  Load your configuration.
2.  Ensure you are logged into Bitwarden (prompting for unlock/login if necessary).
3.  Retrieve your GitHub token.
4.  Present a menu to **Create a new repository** or **Clone an existing repository**.

#### Creating a Repository
*   Prompts for repository name, GitHub username, full name, and email.
*   Creates a private repository on GitHub.
*   Initializes a local folder, sets up the remote, creates a README and LICENSE, and pushes the initial commit.

#### Cloning a Repository
*   Fetches your list of repositories from GitHub.
*   Allows you to select a repository from a list.
*   Configures the appropriate Git credential helper for your OS.
*   Clones the repository.

## Cross-Platform Support

This port is designed to work on Windows, macOS, and Linux.
*   **Windows:** Uses `manager` credential helper.
*   **macOS:** Uses `osxkeychain` credential helper.
*   **Linux:** Creates a custom ephemeral credential helper script using the retrieved token.

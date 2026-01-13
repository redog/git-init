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

        winget install pwsh
*   **Git**

        winget install Git.Git
*   **Bitwarden CLI** (`bw`)

        winget install Bitwarden.CLI
*   **Bitwarden Secrets Manager** (`bws`)

        winget install Microsoft.VCRedist.2015+.x64
        ./MInstall-BWS.ps1

## Getting Started

### 1. Loading keys

* **Create the Secrets in Bitwarden Secrets Manager** (`bws`)
  
    Before configuring the tool create a Bitwarden account and subscribe to the Bitwarden Secrets Manager service.

  1. The user must store their actual API key like GitHub's in the Bitwarden Secrets Manager.
  2. The Bitwarden Secrets Manager API key must be stored in the bitwarden vault.
  3. Ceate or retrieve your Github access token.
    
        ```
        # Our example github access token
        github_pat_11111111112222222333333
        ```
    
1. After logging into the secrets manager for the first time create a company, project, and machine account.
    * Example: contoso, git-init, git-init-apiUser
2. The Secrets Manager CLI can be logged in to using an access token generated for a particular machine account.
3. Once a new machine account is created within a company you can create a bitwarden secrets access token.
4. Do not forget to assign the project and the necessary write permission to the machine account.
   * Only secrets and projects which the machine account has access to may be interacted with using the CLI.
        
        ```
        § bws project list -o table
        ID                                     Name       Creation Date
        -----------------------------------------------------------------------
        02c45a25-d69b-4540-a489-b3d1013ef541   git-init   2026-01-13 19:21:17
        ```
    
    Armed with our new bws access token we can now store our other API tokens in it's secure vault.

          ```
          # Our example bws token
          eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzEyMzQiLCJzY29wZSI6ImFwaSJ9.RmFrZVNpZ25hdHVyZQ
          # bash
          export BWS_ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzEyMzQiLCJzY29wZSI6ImFwaSJ9.RmFrZVNpZ25hdHVyZQ"
          # powershell
          $env:BWS_ACCESS_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyXzEyMzQiLCJzY29wZSI6ImFwaSJ9.RmFrZVNpZ25hdHVyZQ"
 
          bws secret create GITHUB_ACCESS_TOKEN github_pat_11111111112222222333333 02c45a25-d69b-4540-a489-b3d1013ef541
          {
            "id": "7bac9c86-7954-4f79-b853-b3d1014c6742",
            "organizationId": "ac1d066a-785b-49fb-a6e0-b3d1013b30f6",
            "projectId": "02c45a25-d69b-4540-a489-b3d1013ef541",
            "key": "GITHUB_ACCESS_TOKEN",
            "value": "github_pat_11111111112222222333333",
            "note": "",
            "creationDate": "2026-01-13T20:10:14.603711300Z",
            "revisionDate": "2026-01-13T20:10:14.603711400Z"
          }
          ```
    ---
        
          ```config.psd1
          @{
            KeyMap = @(
                @{ Name='GitHub'     ; SecretId='7bac9c86-7954-4f79-b853-b3d1014c6742' ; Env=@{ GITHUB_ACCESS_TOKEN  = '$secret' } }
            )
          }
          ```

    - This one allows us to login to the bw CLI without 2FA challenge? I've forgotten...TODO:fix this README 
    bw web vault -> Settings -> Security -> Keys -> View API Key -> <Enter Master Password> -> View Key
    This is the key for the `bw` CLI tool


### 1. Usage

Run the entry point script from a PowerShell session:

        ```
        Import-Module APIKeys
        Import-Module GitInit
        ```

The init script will:
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

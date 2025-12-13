# git-init

PowerShell-first tooling to bootstrap GitHub repositories using Bitwarden for secret management.

## PowerShell prerequisites

The PowerShell workflow targets PowerShell 7+ (`pwsh`) and relies on native cmdlets instead of Bash tooling.

* PowerShell 7.0 or later
* `git`
* `bw` – Bitwarden CLI
* `bws` – Bitwarden Secrets Manager CLI

The script checks for these dependencies and exits with a helpful error if any are missing. Installation is intentionally left to the user so that the process remains cross-platform.

## Configuration

Secret IDs are normally read from `config.psd1` inside this repository. You can
store them elsewhere by creating a PowerShell data/config script at
`$HOME/.git-init.ps1` or by setting the `GIT_INIT_CONFIG` environment variable
to the path of your preferred config file (JSON, PSD1, or PS1 that returns a
hashtable). The scripts will use that file if present before falling back to the
repo version.

### Configuration Details

The initialization scripts require several IDs to be set in the configuration file. Here's how to get them:

#### `GH_TOKEN_ID`
This is the ID of the secret in Bitwarden Secrets Manager that stores your GitHub Personal Access Token.

To get this ID, you first need to create a secret in Bitwarden Secrets Manager that contains your GitHub token. You can do this with the `bws` command:

```bash
# Get the first project id - adjust for your specific secrets manager project
project_id=$(bws project list | jq -r '.[0].id')

# Store the GitHub access token as a secret named "github-access-token"
bws secret create github-access-token "$GITHUB_ACCESS_TOKEN" "$project_id"

# Get the ID of the secret we just created
GH_TOKEN_ID=$(bws secret list "$project_id" | jq -r '.[] | select(.key == "github-access-token") | .id')

# Export for later use in the session
export GH_TOKEN_ID
```

Then, you can list your secrets to get the ID:

```bash
bws secret list
```

The output will be a JSON array of your secrets. Find the one you just created and copy the `id` value.

#### `BW_API_KEY_ID`
This is the ID of the secret in Bitwarden Secrets Manager that stores your Bitwarden API Key.

Follow the same process as for `GH_TOKEN_ID` to create a secret for your Bitwarden API Key and get its ID.

#### `BWS_ACCESS_TOKEN_ID`
This is the ID of the login item in your Bitwarden vault that stores your Bitwarden Secrets Manager access token.

To get this ID, you first need to create a login item in your Bitwarden vault that contains your BWS access token. You can do this with the `bw` command:

```bash
bw get template item \
| jq --arg name  "bitwarden-secrets-manager-key" \
     --arg notes "Imported via CLI" \
     --arg user  "$BWS_ACCESS_TOKEN_ID" \
     --arg pass  "$BWS_ACCESS_TOKEN" '
      .name  = $name
    | .notes = $notes
    | .login = {
        username: $user,
        password: $pass,
        uris: [ { uri: "https://bitwarden.com", match: 0 } ]
      }' \
| bw encode \
| bw create item
```

Then, you can list your vault items to get the ID or get the token directly with the name/ID:

```bash
bw list items --search secrets-manager
bw get password bitwarden-secrets-manager-key
bw get password a90cacf8-8cbd-4d7a-be58-b3240149cd3e
```

The output will be a JSON array of your vault items. Find the one you just created and copy the `id` value.

## Usage

### PowerShell

Run the entry point with PowerShell Core:

```
pwsh ./init.ps1
```

If you prefer to stay in the same session (to keep `BW_SESSION`, `BWS_ACCESS_TOKEN`, etc.) you can dot-source the script:

```
. ./init.ps1
```

The script walks you through Bitwarden authentication, retrieves your GitHub
token, and then offers to create a new repository or clone an existing one. It
mirrors the original Bash workflow while relying entirely on PowerShell cmdlets
(`Invoke-RestMethod`, `Invoke-WebRequest`, `ConvertFrom-Json`, etc.).

When creating a repository, the script now prompts for the branch name to
publish and defaults to `feature/powershell-port`. After seeding the repository
with an initial commit, it pushes that branch to GitHub so the work is
available as a feature branch immediately.

### Bash (legacy)

The historical Bash workflow is still present for compatibility. Source
`init.sh` if you need the original behavior:

```
source ./init.sh
```

## Git Credential Helper

Both the Bash and PowerShell flows automatically create a `git-credential-env`
helper in `~/.config` on Linux when it isn't found. The helper is now a
PowerShell script that supplies your GitHub token at runtime without storing it
in git config. macOS uses the system keychain and Windows uses Git Credential
Manager by default.

## mkrepo.sh

The original Bash helper is still available. With the access token set in the
environment this script creates a GitHub repository and initializes it locally.

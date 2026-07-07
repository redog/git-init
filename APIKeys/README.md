# APIKeys Module

The **APIKeys** module manages the secure retrieval and injection of API keys and secrets from Bitwarden Secrets Manager (BWS) into your current PowerShell session.

It reads a JSON configuration file (`config.json`, shared with the bash `init.sh`)
that maps local environment variables to secrets stored in Bitwarden. PowerShell
Data Files (`.psd1`) are still accepted for backwards compatibility.

## Features

- **Secure Retrieval:** Fetches secrets directly from BWS into environment variables.
- **Flexible Configuration:** Map any secret to any environment variable using a JSON config file (legacy `.psd1` also accepted).
- **Bitwarden Integration:** Automatically handles `bws` authentication using a BWS Access Token stored in your Bitwarden Vault.
- **Session Management:** Can clear injected secrets from the environment.
- **OS Keychain Caching:** Persists the vault session, BWS token, and secret values in the native credential store (Windows Credential Manager / macOS Keychain / Linux libsecret) so new shells load without prompts or network calls.
- **Optional Master-Password Storage:** Explicit opt-in to store the Bitwarden master password in the OS keychain for fully prompt-free unlocks — with just as explicit removal.

## Configuration

The module is configured using a hashtable, typically loaded from a `.json` file
(via `Import-APIKeysConfig`); legacy `.psd1` files are still supported.

### Config File Structure (`config.json`)

See the repo-root `config.sample.json` for a complete example.

The configuration file must contain an object with the following keys:

- **`BwsCliPath`** (Optional): Path to the `bws` executable. Defaults to `bws`.
- **`BwsTokenItem`** (Optional): The Name or ID of the item in your Bitwarden Vault that contains the BWS Access Token. Defaults to "Bitwarden Secrets Manager Service Account".
- **`KeyMap`**: An array of hashtables, where each entry defines a secret to load.

### KeyMap Entry Format

Each entry in `KeyMap` should have:

- **`Name`**: A friendly name for the secret (e.g., "GitHub").
- **`SecretId`**: The UUID of the secret in Bitwarden Secrets Manager.
- **`Env`**: A hashtable mapping environment variable names to values.
    - Use `'$secret'` as the value to inject the actual secret retrieved from BWS.
    - Any other string will be set as a literal value.

**Example:**

```json
{
  "KeyMap": [
    {
      "Name": "GitHub",
      "SecretId": "857d0c2c-cfe0-4e6d-995c-b1690020f8fb",
      "Env": { "GITHUB_ACCESS_TOKEN": "$secret" }
    }
  ]
}
```

## Functions

### `Import-APIKeysConfig`

Loads configuration from a `.json` (canonical) or `.psd1` (legacy) file.

```powershell
Import-APIKeysConfig -Path "./config.json"
```

### `Set-APIKeysConfig`

Manually sets the configuration for the module.

```powershell
Set-APIKeysConfig -BwsTokenItem "My BWS Token" -KeyMap $myKeyMap
```

### `Set-AllAPIKeys` (Alias: `load_keys`)

Loads the configured keys into the current session.

- **`-Only <string[]>`**: Load only specific keys by name or environment variable.
- **`-Except <string[]>`**: Skip specific keys.
- **`-Quiet`**: Suppress output.

```powershell
# Load all keys
Set-AllAPIKeys

# Load only GitHub key
Set-AllAPIKeys -Only GitHub
```

### `Clear-APIKeyEnv`

Removes the environment variables set by the module.

- **`-ClearBitwardenSession`**: Also removes `BW_SESSION` and `BWS_ACCESS_TOKEN`.

```powershell
Clear-APIKeyEnv -ClearBitwardenSession
```

## Keychain & Session Functions

All credentials are stored in the OS-native credential store under the
`git-init` service (Windows Credential Manager, macOS Keychain, or Linux
GNOME Keyring / libsecret via `secret-tool`).

### `Clear-GitInitSession`

Removes the cached vault session, BWS token, and every cached secret value
from the keychain, and unsets them in the environment.

- **`-IncludeMasterPassword`**: Also remove the stored master password (kept by default — sessions are expiring caches, the password is a deliberate opt-in).

```powershell
Clear-GitInitSession                        # session + secrets only
Clear-GitInitSession -IncludeMasterPassword # full wipe
```

### `Save-GitInitMasterPassword` (opt-in)

Stores the Bitwarden master password in the OS keychain so `Connect-Bitwarden`
can unlock the vault without ever prompting. The password is:

- prompted for interactively — never accepted as a parameter, so it cannot leak into shell history;
- **validated** by actually unlocking the vault before anything is stored;
- handed to `bw unlock --passwordenv` via an environment variable, never via disk or a process argument list.

If it ever stops unlocking the vault (e.g. after a password change),
`Connect-Bitwarden` removes it from the keychain automatically and falls back
to the interactive prompt.

> **Trade-off:** cached sessions expire, the master password does not.
> Anything that can read your unlocked credential store can read it. Only opt
> in on machines where that is acceptable.

```powershell
Save-GitInitMasterPassword     # prompt, validate, store
```

### `Remove-GitInitMasterPassword` / `Test-GitInitMasterPassword`

```powershell
Test-GitInitMasterPassword     # $true if one is stored
Remove-GitInitMasterPassword   # delete it from the keychain
```

### `Save-GitInitSession` / `Restore-GitInitSession`

Manually save the current `BW_SESSION` / `BWS_ACCESS_TOKEN` to the keychain,
or restore them into the environment. (The main flows do this automatically.)

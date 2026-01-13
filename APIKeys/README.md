# APIKeys Module

The **APIKeys** module manages the secure retrieval and injection of API keys and secrets from Bitwarden Secrets Manager (BWS) into your current PowerShell session.

It is designed to be configured via a PowerShell Data File (`.psd1`) which maps local environment variables to secrets stored in Bitwarden.

## Features

- **Secure Retrieval:** Fetches secrets directly from BWS into environment variables.
- **Flexible Configuration:** Map any secret to any environment variable using a `.psd1` file.
- **Bitwarden Integration:** Automatically handles `bws` authentication using a BWS Access Token stored in your Bitwarden Vault.
- **Session Management:** Can clear injected secrets from the environment.

## Configuration

The module is configured using a hashtable, typically loaded from a `.psd1` file.

### Config File Structure (`config.psd1`)

See `config.sample.psd1` for a complete example.

The configuration file must return a hashtable with the following keys:

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

```powershell
@{
    KeyMap = @(
        @{
            Name     = 'GitHub'
            SecretId = '857d0c2c-cfe0-4e6d-995c-b1690020f8fb'
            Env      = @{ GITHUB_ACCESS_TOKEN = '$secret' }
        }
    )
}
```

## Functions

### `Import-APIKeysConfig`

Loads configuration from a `.psd1` file.

```powershell
Import-APIKeysConfig -Path "./config.psd1"
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

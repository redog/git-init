# Git-Init

Tools to streamline the initialization and cloning of GitHub repositories,
with integrated secret management using Bitwarden / Bitwarden Secrets Manager.

Two front-ends share a **single JSON configuration file** and the same key-map
schema:

1.  **[PowerShell version](#powershell-version)** — `init.ps1` (cross-platform)
2.  **[Shell version](#shell-version)** — `init.sh` (Linux / macOS)

---

## Configuration (shared)

Both implementations read the same configuration file. Lookup order:

1.  `$GIT_INIT_CONFIG` (env var)
2.  `~/.git-init.json`
3.  `<repo>/config.json`
4.  `<repo>/config.psd1` or `~/.git-init.psd1` (PowerShell legacy, still supported)

Copy `config.sample.json` to `config.json` and fill in your IDs:

```json
{
  "BwsCliPath": "bws",
  "BwsTokenItem": "Bitwarden Secrets Manager Service Account",
  "KeyMap": [
    {
      "Name": "GitHub",
      "SecretId": "00000000-0000-0000-0000-000000000000",
      "Env": { "GITHUB_ACCESS_TOKEN": "$secret" }
    }
  ]
}
```

Field meanings:

| Key            | Purpose                                                                    |
| -------------- | -------------------------------------------------------------------------- |
| `BwsCliPath`   | Path to the `bws` executable (default: `bws`).                             |
| `BwsTokenItem` | Name **or** UUID of the bw vault item that contains the BWS access token.  |
| `KeyMap`       | Array of `{ Name, SecretId, Env }` entries.                                |

Inside an `Env` map, the literal string `$secret` is replaced with the secret
value retrieved from BWS. Any other value is set as-is (useful for setting flags
like `LANGCHAIN_TRACING_V2: "true"` alongside an API key).

`config.json` is `.gitignore`-d. The token UUIDs are not secrets themselves, but
treating them as personal config keeps your repo clean.

---

## PowerShell version

Cross-platform PowerShell 7+ implementation.

### Prerequisites

1.  **PowerShell 7+** (`pwsh`)
2.  **Git**
3.  **Bitwarden CLI** (`bw`) — for vault unlocking
4.  **Bitwarden Secrets Manager CLI** (`bws`) — for secret retrieval
5.  **Rust / Cargo** — for installing `bws`

### Install on Windows

```powershell
winget install pwsh
winget install Git.Git
winget install Bitwarden.CLI
winget install Rustlang.Rustup
& ./MInstall-BWS.ps1
```

### Usage

```powershell
. ./init.ps1                # default flow (load keys + interactive menu)
. ./init.ps1 -Reload        # force-reload keys even if already in env
. ./init.ps1 -Reconfigure   # re-prompt for git config (name, email, gh user)
```

Exposed cmdlets after sourcing:

| Cmdlet / alias               | Purpose                                              |
| ---------------------------- | ---------------------------------------------------- |
| `Set-AllAPIKeys` / `load_keys` | Load keys per `KeyMap` (`-Only`, `-Except`, `-Quiet`). |
| `Clear-APIKeyEnv`            | Unset all key-map env vars (`-ClearBitwardenSession`). |
| `Update-VaultAPIKey`         | Update a secret in BWS and reload it locally.        |
| `Get-APIKeyMap`              | Print the loaded key map.                            |
| `Connect-Bitwarden`          | Ensure `bw` is logged-in and unlocked.               |
| `Get-GHUser` / `Get-GHRepositories` / `New-GHRepository` | GitHub helpers. |

---

## Shell version

Bash implementation matching the PowerShell feature set.

### Prerequisites

`curl`, `unzip`, `git`, `cargo` (Rust). Run `./setup.sh` to install:

* `jq` — JSON processor
* `bw` — Bitwarden CLI
* `bws` — Bitwarden Secrets Manager CLI

### Usage

```bash
# Quick one-liner: load keys, install credential helper, run interactive menu.
source <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)

# Local clone, with options:
source ./init.sh --reload         # force key reload
source ./init.sh --reconfigure    # re-prompt for git identity
source ./init.sh --no-menu        # set up env, skip the menu
./init.sh                          # executed (not sourced) — env stays in subshell
```

Exposed functions after sourcing:

| Function                          | Purpose                                              |
| --------------------------------- | ---------------------------------------------------- |
| `gi_load_keys [--only N1,N2] [--except N1,N2] [--quiet]` | Load keys per `KeyMap`.    |
| `gi_clear_keys [--all]`           | Unset all key-map env vars (`--all` also clears bw session). |
| `gi_update_key <name> [value]`    | Update a secret in BWS and reload it locally.        |
| `gi_list_keys`                    | List `Name`, `SecretId`, env vars per entry.         |
| `gi_get_secret <secret-id>`       | Fetch a single value from BWS.                       |
| `gi_connect_bitwarden`            | Ensure `bw` is logged-in and unlocked.               |
| `gi_get_bws_token`                | Bootstrap `BWS_ACCESS_TOKEN` from the bw vault item. |
| `gi_gh_user` / `gi_gh_repos` / `gi_gh_new_repo <name>` | GitHub helpers.                |
| `gi_init_local_repo <repo> <gh-user> <full-name> <email>` | Local init + first push. |
| `gi_menu`                         | Interactive create/clone menu.                       |

### Sourcing safety

`init.sh` enables `set -euo pipefail` only inside its own main body, and a
save/restore wrapper guarantees your shell options are returned to whatever they
were before sourcing — **on every exit path**, including failures. You can
re-source the script repeatedly from your `.bashrc` without `errexit` /
`pipefail` leaking into your interactive shell.

### Git credential helper

`init.sh` writes `~/.config/git-credential-env` once. The helper reads
`GITHUB_ACCESS_TOKEN` (or fetches it via `bws` if `GH_TOKEN_ID` is set) so Git
can authenticate without storing the token in your repo config.

---

## Migrating from the legacy `config.env` / `config.psd1`

The previous shell version read four IDs from `config.env`:
`GH_TOKEN_ID`, `BW_API_KEY_ID`, `BWS_ACCESS_TOKEN_ID`, `BW_CLIENTID`.

In the unified JSON config:

* `BWS_ACCESS_TOKEN_ID` → `BwsTokenItem` (use the same UUID, or the item name)
* `GH_TOKEN_ID` → a `KeyMap` entry with `Name: "GitHub"` and the same `SecretId`,
  mapped to `GITHUB_ACCESS_TOKEN`.
* `BW_CLIENTID` and `BW_API_KEY_ID` are no longer used by `init.sh`. To do a
  headless `bw login --apikey`, set `BW_CLIENTID` / `BW_CLIENTSECRET` in your
  shell before sourcing (matches the PowerShell behavior).

The PowerShell `config.psd1` format is still read as a fallback, but new setups
should use `config.json`.

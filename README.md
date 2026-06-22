# Git-Init

Tools to streamline the initialization and cloning of GitHub repositories,
with integrated secret management using Bitwarden / Bitwarden Secrets Manager.

Initially built as a shell script for secrets management but has grown into a 
vibe coded prototype that's escaped containment.

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

**You don't need to author this file by hand.** Run `init.sh` or `init.ps1`
with no existing config and it will prompt you for the BWS token-item and your
GitHub PAT secret UUID, then write `~/.git-init.json` for you. From there you
manage the file with shell/PS functions.

Copy `config.sample.json` to `config.json` only if you prefer a static template:

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

## OS Keychain Caching

Both implementations cache credentials in the OS native credential store so that
new shells load without any network calls or password prompts.

**What gets cached:**

| Credential | Key | Purpose |
| --- | --- | --- |
| Bitwarden vault session | `bw_session` | Skips `bw unlock` master-password prompt |
| BWS service-account token | `bws_token` | Skips fetching the token from the vault |
| Each secret value | `secret:<uuid>` | Skips `bws secret get` network call per key |

The last point is the most impactful. Every `bws secret get` is an HTTPS round-trip
(~100–300 ms each). With a full warm cache the entire load sequence is local
keychain reads — startup is essentially instantaneous regardless of how many keys
are in your `KeyMap`.

**Platform backends:**

| Platform | Backend                                   | Requirement                                                          |
| -------- | ----------------------------------------- | -------------------------------------------------------------------- |
| macOS    | macOS Keychain (`security` CLI)           | Built-in, no setup needed                                            |
| Linux    | GNOME Keyring / libsecret (`secret-tool`) | `app-crypt/libsecret` (Gentoo) · `libsecret-tools` (Debian / Ubuntu) |
| Windows  | Windows Credential Manager (WinRT API)    | Built-in, no setup needed                                            |

**Cache invalidation:**

The cache stays valid until you explicitly clear it. Use `--reload` / `-Reload`
to bypass the secret cache and re-fetch fresh values from BWS (e.g. after
rotating a secret), or clear everything at once before re-sourcing:

```bash
# bash / zsh — bypass cache for this run only
source init.sh --reload

# bash / zsh — wipe all cached credentials (session + every secret)
gi_session_clear && source init.sh
```

```powershell
# PowerShell — bypass cache for this run only
. ./init.ps1 -Reload

# PowerShell — wipe all cached credentials (session + every secret)
Clear-GitInitSession; . ./init.ps1
```

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
# chezmoi install from pwsh
iex "&{$(irm 'https://get.chezmoi.io/ps1')} -b '~/bin'"
# Windows
winget install pwsh
winget install Git.Git
winget install Bitwarden.CLI
winget install Rustlang.Rustup
& ./MInstall-BWS.ps1
```

### Usage

```powershell
. ./init.ps1                # default: load keys, show config path + summary
. ./init.ps1 -Verbose       # also show per-key confirmations and keychain messages
. ./init.ps1 -Quiet         # print nothing (errors still appear on stderr)
. ./init.ps1 -Reload        # force-reload keys even if already in env
. ./init.ps1 -Reconfigure   # re-prompt for git config (name, email, gh user)
. ./init.ps1 -Menu          # set up env and run the interactive create/clone menu
```

### Shell profile integration

Add to your PowerShell profile so keys are available in every new session:

```powershell
# $PROFILE  (e.g. ~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1)
. "$HOME\path\to\git-init\init.ps1" -Quiet
```

`-Quiet` keeps startup silent. Thanks to keychain caching the vault is not
re-unlocked on subsequent shells — it simply restores the saved session. Errors
(expired session, missing config) still appear on stderr. Replace `-Quiet` with
`-Verbose` while debugging.

To find your profile path:

```powershell
echo $PROFILE
```

### Exposed cmdlets

| Cmdlet / alias                     | Purpose                                                        |
| ---------------------------------- | -------------------------------------------------------------- |
| `Set-AllAPIKeys` / `load_keys`     | Load keys per `KeyMap` (`-Only`, `-Except`, `-Quiet`).         |
| `Clear-APIKeyEnv`                  | Unset all key-map env vars (`-ClearBitwardenSession`).         |
| `Update-VaultAPIKey`               | Update a secret in BWS and reload it locally.                  |
| `Get-APIKeyMap`                    | Print the loaded key map.                                      |
| `Connect-Bitwarden`                | Ensure `bw` is logged-in and unlocked.                         |
| `Initialize-APIKeysConfigFile`     | Create a new config file (`-Path`, `-BwsTokenItem`, `-BwsCliPath`). |
| `Add-APIKey -Name -SecretId -Env`  | Add or update a KeyMap entry and persist.                      |
| `Remove-APIKey -Name`              | Drop a KeyMap entry and persist.                               |
| `Set-APIKeysConfigField -Field -Value` | Set `BwsCliPath` or `BwsTokenItem`.                        |
| `Show-APIKeysConfig`               | Dump current config (path + map).                              |
| `Save-APIKeysConfig [-Path]`       | Persist current in-memory config.                              |
| `Get-GHUser` / `Get-GHRepositories` / `New-GHRepository` | GitHub helpers.               |
| `Clear-GitInitSession`             | Remove session from keychain and unset env vars.               |
| `Save-GitInitSession`              | Manually save current `BW_SESSION` / `BWS_ACCESS_TOKEN` to keychain. |
| `Restore-GitInitSession`           | Manually restore session from keychain into env.               |
| `Save-GitInitCredential -Key -Value` | Low-level: write one credential to the keychain.             |
| `Get-GitInitCredential -Key`       | Low-level: read one credential from the keychain.              |
| `Remove-GitInitCredential -Key`    | Low-level: delete one credential from the keychain.            |
| `Set-GitInitVerbosity -Level <0-2>` | Set output level (0 quiet · 1 normal · 2 verbose).            |

---

## Shell version

Bash / zsh implementation matching the PowerShell feature set.

### Prerequisites

`curl`, `unzip`, `git`, `cargo` (Rust). Run `./setup.sh` to install:

* `jq` — JSON processor
* `bw` — Bitwarden CLI
* `bws` — Bitwarden Secrets Manager CLI

### Usage

```bash
source ./init.sh                # default: load keys, show config path + summary
source ./init.sh -v             # also show per-key confirmations and keychain messages
source ./init.sh -q             # print nothing (errors still appear on stderr)
source ./init.sh --reload       # force key reload
source ./init.sh --reconfigure  # re-prompt for git identity
source ./init.sh --menu         # set up env and run the interactive create/clone menu
./init.sh                       # executed (not sourced) — env stays in subshell
```

**Quick start: install pre-reqs, load keys, install credential helper.**
- Converted everything to chezmoi which pulls deps for me now:
- I bootstrap from a private rc repo by using a public gist file like this.
```bash
source <(curl -fsLS https://gist.githubusercontent.com/redog/8472dd896a39413a43a76618d2b12ab1/raw/f6753977db292e71468ec7d2c3359a0d58dab105/puss-in-bootstrap.sh)
```
- chezmoi handles my pre-reqs in a run_once_before_install_prereqs.sh script.
 *(See: https://gist.github.com/redog/2f97dcaab1564f55c17f0ba431ecfc2f)*
```bash
source <(curl -fsLS get.chezmoi.io) -- init --apply git@github.com:redog/rc.git
```

**You could also just export the GH_TOKEN env variable manually before init --apply like:**
- Install chezmoi natively:
```bash
sh -c "$(curl -fsLS get.chezmoi.io)"
```

- Init and apply using the token in the URL:
```bash
~/bin/chezmoi init --apply https://oauth2:${GH_TOKEN}@github.com/${YOUR_USERNAME}/dotfiles.git
```

### Shell profile integration

Add to `~/.bashrc` or `~/.zshrc` so keys are available in every new interactive
shell. With keychain caching in place, subsequent shells restore the saved session
without prompting for the master password:

```bash
# ~/.bashrc or ~/.zshrc
source /path/to/git-init/init.sh -q
```

`-q` keeps startup silent. If the session has expired or the vault needs
unlocking, you will see only the `bw unlock` prompt itself — no other output.
Remove `-q` or swap it for `-v` while debugging.

For a remote / curl-based setup (e.g. via chezmoi dotfiles):

```bash
# ~/.zshrc  — sourced from a URL; -q keeps it silent on every shell open
source <(curl -fsLS https://raw.githubusercontent.com/you/rc/main/init.sh) -q
```

If you only want to load keys when the env vars are actually missing (skipping
even the curl on warm shells), wrap it in a guard:

```bash
# ~/.bashrc
if [[ -z "${GITHUB_ACCESS_TOKEN:-}" ]]; then
  source /path/to/git-init/init.sh -q
fi
```

### Exposed functions

| Function                          | Purpose                                              |
| --------------------------------- | ---------------------------------------------------- |
| `gi_load_keys [--only N1,N2] [--except N1,N2] [--quiet]` | Load keys per `KeyMap`. Per-key messages shown only at `-v`. |
| `gi_clear_keys [--all]`           | Unset all key-map env vars (`--all` also clears session). |
| `gi_update_key <name> [value]`    | Update a secret in BWS and reload it locally.        |
| `gi_list_keys`                    | List `Name`, `SecretId`, env vars per entry.         |
| `gi_get_secret <secret-id>`       | Fetch a single value from BWS.                       |
| `gi_config_init [path]`           | Interactively create a new config file.              |
| `gi_config_show`                  | Pretty-print the current config + path.              |
| `gi_config_set <field> <value>`   | Update `BwsCliPath` or `BwsTokenItem` and persist.   |
| `gi_config_add_key [name] [id] [VAR\|VAR=value] [...]` | Add/update a KeyMap entry. Prompts for missing args. |
| `gi_config_remove_key <name>`     | Drop a KeyMap entry by name.                         |
| `gi_connect_bitwarden`            | Ensure `bw` is logged-in and unlocked.               |
| `gi_get_bws_token`                | Bootstrap `BWS_ACCESS_TOKEN` from the bw vault item. |
| `gi_session_clear`                | Remove session from keychain and unset env vars.     |
| `gi_keychain_save <key> <value>`  | Low-level: write one credential to the OS keychain.  |
| `gi_keychain_load <key>`          | Low-level: read one credential from the OS keychain. |
| `gi_keychain_clear <key>`         | Low-level: delete one credential from the OS keychain. |
| `gi_gh_user` / `gi_gh_repos` / `gi_gh_new_repo <name>` | GitHub helpers.                |
| `gi_init_local_repo <repo> <gh-user> <full-name> <email>` | Local init + first push.    |
| `gi_menu`                         | Interactive create/clone menu.                       |

Examples:

```bash
# Add a key. Default value '$secret' gets replaced with the BWS lookup.
gi_config_add_key OpenAI fbe0690e-fb43-4e91-b49c-b0b50039847a OPENAI_API_KEY

# One secret, multiple env vars (one with a literal flag).
gi_config_add_key LangSmith ad3f662b-9c78-4d22-9e15-b2c70147eabc \
    LANGCHAIN_API_KEY LANGSMITH_API_KEY LANGCHAIN_TRACING_V2=true

gi_config_set BwsTokenItem 'My Token Item'
gi_config_remove_key OpenAI

# Force full re-auth (e.g. after rotating the BWS service-account token).
gi_session_clear && source init.sh
```

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

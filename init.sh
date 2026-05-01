#!/usr/bin/env bash
# git-init: bootstrap GitHub repos with Bitwarden-managed secrets.
#
# Run executed for the interactive menu, or source for the env-loading flow plus
# the gi_* helper functions (load/clear/update keys, GitHub API helpers, etc.).

GI_VERSION="0.2.0"
MYINIT="git-init"

# Sourced-vs-executed detection.
_GI_SOURCED=0
[[ ${BASH_SOURCE[0]} != "${0:-}" ]] && _GI_SOURCED=1

if (( ! _GI_SOURCED )); then
  echo "Tip: run 'source init.sh' (or 'source <(curl -sS .../init.sh)') to keep variables and helper functions in your shell."
fi

#==============================================================================
# common helpers
#==============================================================================

gi_safe_exit() {
  local code=${1:-0}
  if (( _GI_SOURCED )); then
    return "$code"
  else
    exit "$code"
  fi
}

gi_fail() {
  local code=${1:-1}
  shift || true
  [[ $# -gt 0 ]] && echo "$*" >&2
  return "$code"
}

#==============================================================================
# configuration
#==============================================================================

_GI_CONFIG_JSON=""
_GI_CONFIG_PATH=""

gi_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

gi_locate_config() {
  if [[ -n "${GIT_INIT_CONFIG:-}" && -f "${GIT_INIT_CONFIG}" ]]; then
    echo "${GIT_INIT_CONFIG}"; return 0
  fi
  if [[ -f "$HOME/.git-init.json" ]]; then
    echo "$HOME/.git-init.json"; return 0
  fi
  local dir
  dir="$(gi_script_dir)"
  if [[ -f "$dir/config.json" ]]; then
    echo "$dir/config.json"; return 0
  fi
  return 1
}

gi_load_config() {
  local path
  if ! path=$(gi_locate_config); then
    gi_fail 1 "Config not found. Tried \$GIT_INIT_CONFIG, ~/.git-init.json, $(gi_script_dir)/config.json"
    return 1
  fi
  _GI_CONFIG_PATH="$path"
  _GI_CONFIG_JSON=$(cat "$path") || return 1
  if ! echo "$_GI_CONFIG_JSON" | jq empty 2>/dev/null; then
    gi_fail 1 "Invalid JSON in config: $path"
    return 1
  fi
  return 0
}

gi_config_get() {
  # Usage: gi_config_get '<jq filter>'
  [[ -n "$_GI_CONFIG_JSON" ]] || gi_load_config || return 1
  echo "$_GI_CONFIG_JSON" | jq -r "$1"
}

#==============================================================================
# bitwarden / bws bootstrap
#==============================================================================

_gi_bws() {
  local cli
  cli=$(gi_config_get '.BwsCliPath // "bws"')
  command "$cli" "$@"
}

gi_connect_bitwarden() {
  command -v bw &>/dev/null || { echo "Bitwarden CLI 'bw' not found in PATH." >&2; return 1; }

  local status
  status=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "")

  if [[ "$status" == "unauthenticated" || -z "$status" ]]; then
    if [[ -n "${BW_CLIENTID:-}" && -n "${BW_CLIENTSECRET:-}" ]]; then
      echo "🤖 Logging in to Bitwarden CLI with API key..."
      BW_CLIENTID="$BW_CLIENTID" BW_CLIENTSECRET="$BW_CLIENTSECRET" bw login --apikey \
        || { echo "API key login failed." >&2; return 1; }
    else
      echo "👤 Logging in to Bitwarden CLI..."
      bw login || { echo "Interactive login failed." >&2; return 1; }
    fi
    status=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null || echo "")
  fi

  if [[ "$status" == "locked" && -z "${BW_SESSION:-}" ]]; then
    echo "🔓 Unlocking Bitwarden vault..."
    local session
    session=$(bw unlock --raw) || { echo "Unlock failed." >&2; return 1; }
    [[ -n "$session" ]] || { echo "Empty session returned by bw unlock." >&2; return 1; }
    export BW_SESSION="$session"
    echo "✅ Vault unlocked."
  fi
  return 0
}

gi_get_bws_token() {
  if [[ -n "${BWS_ACCESS_TOKEN:-}" ]]; then
    return 0
  fi

  gi_connect_bitwarden || return 1

  local item_ref token_item token
  item_ref=$(gi_config_get '.BwsTokenItem // ""')
  [[ -n "$item_ref" ]] || { echo "BwsTokenItem not configured in $_GI_CONFIG_PATH" >&2; return 1; }

  token_item=$(bw get item "$item_ref" 2>/dev/null) \
    || { echo "Could not fetch bw item '$item_ref'." >&2; return 1; }

  token=$(echo "$token_item" | jq -r '.notes // empty')
  if [[ -z "$token" ]]; then
    token=$(echo "$token_item" | jq -r '(.fields // [])[] | select(.name=="token") | .value' | head -n1)
  fi
  if [[ -z "$token" ]]; then
    token=$(echo "$token_item" | jq -r '.login.password // empty')
  fi

  if [[ -z "$token" ]]; then
    echo "Could not extract BWS access token from item '$item_ref' (notes / 'token' field / login.password)." >&2
    return 1
  fi

  export BWS_ACCESS_TOKEN="$token"

  local cli
  cli=$(gi_config_get '.BwsCliPath // "bws"')
  command -v "$cli" &>/dev/null \
    || { echo "Bitwarden Secrets Manager CLI '$cli' not found in PATH." >&2; return 1; }
  return 0
}

#==============================================================================
# secrets / key map
#==============================================================================

gi_get_secret() {
  # Usage: gi_get_secret <secret-id>
  local id="$1"
  [[ -n "$id" ]] || { echo "Usage: gi_get_secret <secret-id>" >&2; return 1; }
  local out
  out=$(_gi_bws secret get "$id" -o json 2>/dev/null) || return 1
  echo "$out" | jq -r '.value'
}

gi_list_keys() {
  [[ -n "$_GI_CONFIG_JSON" ]] || gi_load_config || return 1
  echo "$_GI_CONFIG_JSON" | jq -r '.KeyMap[] | "\(.Name)\t\(.SecretId)\t\(.Env | keys | join(","))"'
}

_gi_in_csv() {
  # _gi_in_csv "needle" "a,b,c"
  local needle="$1" csv="$2"
  [[ ",$csv," == *",$needle,"* ]]
}

gi_load_keys() {
  local only="" except="" quiet=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only)   only="$2"; shift 2 ;;
      --except) except="$2"; shift 2 ;;
      --quiet)  quiet=1; shift ;;
      -h|--help)
        cat <<EOF
Usage: gi_load_keys [--only N1,N2] [--except N1,N2] [--quiet]
EOF
        return 0 ;;
      *) echo "gi_load_keys: unknown option '$1'" >&2; return 1 ;;
    esac
  done

  [[ -n "$_GI_CONFIG_JSON" ]] || gi_load_config || return 1
  gi_get_bws_token || return 1

  local entries
  entries=$(echo "$_GI_CONFIG_JSON" | jq -c '.KeyMap[]?')
  if [[ -z "$entries" ]]; then
    echo "KeyMap is empty in $_GI_CONFIG_PATH." >&2
    return 1
  fi

  local ok=0 fail=0
  while IFS= read -r entry; do
    local name secret_id
    name=$(echo "$entry" | jq -r '.Name')
    secret_id=$(echo "$entry" | jq -r '.SecretId')

    if [[ -n "$only" ]] && ! _gi_in_csv "$name" "$only"; then continue; fi
    if [[ -n "$except" ]] && _gi_in_csv "$name" "$except"; then continue; fi

    local secret
    if ! secret=$(gi_get_secret "$secret_id") || [[ -z "$secret" ]]; then
      echo "Could not load $name (SecretId: $secret_id)." >&2
      ((fail++)) || true
      continue
    fi

    while IFS=$'\t' read -r env_name value; do
      [[ -z "$env_name" ]] && continue
      if [[ "$value" == '$secret' ]]; then
        value="$secret"
      fi
      export "$env_name=$value"
    done < <(echo "$entry" | jq -r '.Env | to_entries[] | "\(.key)\t\(.value)"')

    (( quiet )) || echo "$name loaded."
    ((ok++)) || true
  done <<< "$entries"

  (( quiet )) || echo "API keys loaded. Success: $ok  Failed: $fail"
  (( fail == 0 ))
}

gi_clear_keys() {
  local clear_session=0
  [[ "${1:-}" == "--all" ]] && clear_session=1

  [[ -n "$_GI_CONFIG_JSON" ]] || gi_load_config || return 1

  while IFS= read -r env_name; do
    [[ -n "$env_name" ]] && unset "$env_name"
  done < <(echo "$_GI_CONFIG_JSON" | jq -r '.KeyMap[].Env | keys[]')

  if (( clear_session )); then
    unset BW_SESSION BWS_ACCESS_TOKEN
  fi
}

gi_update_key() {
  local name="$1" new_value="${2:-}"
  [[ -n "$name" ]] || { echo "Usage: gi_update_key <name> [value]" >&2; return 1; }

  if [[ -z "$new_value" ]]; then
    read -r -s -p "Enter new value for $name: " new_value
    echo
  fi

  [[ -n "$_GI_CONFIG_JSON" ]] || gi_load_config || return 1

  local secret_id
  secret_id=$(echo "$_GI_CONFIG_JSON" | jq -r --arg n "$name" '.KeyMap[] | select(.Name==$n) | .SecretId')
  [[ -n "$secret_id" ]] || { echo "Key '$name' not found in config." >&2; return 1; }

  gi_get_bws_token || return 1

  echo "Updating secret '$name' ($secret_id) in Bitwarden Secrets Manager..."
  local out
  if ! out=$(_gi_bws secret edit "$secret_id" --value "$new_value" -o json 2>&1); then
    echo "Failed to update secret in BWS: $out" >&2
    return 1
  fi
  echo "✅ Vault updated successfully for '$name'."

  echo "🔄 Reloading '$name' into current environment..."
  gi_load_keys --only "$name" --quiet || return 1
  echo "🚀 Done. Your shell is using the new value."
}

#==============================================================================
# github API
#==============================================================================

_gi_gh_curl() {
  [[ -n "${GITHUB_ACCESS_TOKEN:-}" ]] || { echo "GITHUB_ACCESS_TOKEN is not set. Run gi_load_keys first." >&2; return 1; }
  curl -fsSL \
    -H "Authorization: Bearer $GITHUB_ACCESS_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "$@"
}

gi_gh_user() {
  _gi_gh_curl "https://api.github.com/user" | jq -r '.login'
}

gi_gh_repos() {
  local page=1 per_page=100 response count
  while :; do
    response=$(_gi_gh_curl "https://api.github.com/user/repos?per_page=${per_page}&page=${page}") || return 1
    count=$(echo "$response" | jq 'length')
    [[ "$count" -eq 0 ]] && break
    echo "$response" | jq -r '.[].full_name'
    [[ "$count" -lt "$per_page" ]] && break
    ((page++))
  done
}

gi_gh_new_repo() {
  local name="$1"
  [[ -n "$name" ]] || { echo "Usage: gi_gh_new_repo <name>" >&2; return 1; }
  [[ -n "${GITHUB_ACCESS_TOKEN:-}" ]] || { echo "GITHUB_ACCESS_TOKEN is not set." >&2; return 1; }

  local body status response http_body
  body=$(jq -n --arg n "$name" '{name:$n, description:"Created with git-init", private:true}')
  response=$(curl -sSL -w "\n%{http_code}" \
    -H "Authorization: Bearer $GITHUB_ACCESS_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "$body" "https://api.github.com/user/repos")
  status=$(echo "$response" | tail -n1)
  http_body=$(echo "$response" | sed '$d')

  case "$status" in
    201) echo "$http_body" | jq -r '.full_name'; return 0 ;;
    422) echo "Repository name '$name' already exists." >&2; return 1 ;;
    *)   echo "Failed to create repository: HTTP $status" >&2
         [[ -n "$http_body" ]] && echo "$http_body" >&2
         return 1 ;;
  esac
}

#==============================================================================
# git credential helper
#==============================================================================

gi_ensure_credential_helper() {
  local helper="$HOME/.config/git-credential-env"
  [[ -f "$helper" ]] && return 0
  mkdir -p "$HOME/.config"
  cat >"$helper" <<'EOF'
#!/usr/bin/env bash
set -eu
op=${1:-}
while IFS= read -r line && [[ -n $line ]]; do :; done
[[ $op == get ]] || exit 0
token=${GITHUB_ACCESS_TOKEN:-}
if [[ -z $token ]]; then
    [[ -n ${GH_TOKEN_ID:-} ]] || { echo "GH_TOKEN_ID not set" >&2; exit 1; }
    token=$(bws secret get "$GH_TOKEN_ID" -o json | jq -r .value)
fi
echo "username=x-access-token"
echo "password=$token"
EOF
  chmod +x "$helper"
}

gi_credential_helper_arg() {
  local helper="$HOME/.config/git-credential-env"
  case "$OSTYPE" in
    darwin*)        echo "osxkeychain" ;;
    msys*|cygwin*)  echo "manager" ;;
    *)              echo "$helper" ;;
  esac
}

#==============================================================================
# local repository init
#==============================================================================

gi_init_local_repo() {
  local repo_name="$1" username="$2" full_name="$3" email="$4"
  [[ -n "$repo_name" && -n "$username" && -n "$full_name" && -n "$email" ]] \
    || { echo "Usage: gi_init_local_repo <repo> <gh-username> <full-name> <email>" >&2; return 1; }
  [[ -d "$repo_name" ]] && { echo "Directory '$repo_name' already exists." >&2; return 1; }

  mkdir "$repo_name" || return 1
  cd "$repo_name" || return 1

  git init
  git config user.name "$full_name"
  git config user.email "$email"
  git config credential.helper "$(gi_credential_helper_arg)"

  git remote add origin "https://github.com/$username/$repo_name.git"

  echo "$repo_name by $username" > README.md
  curl -fsSL https://www.gnu.org/licenses/gpl-3.0.txt > LICENSE

  git add .
  git commit -m "Initial commit"
  git branch -M main
  git push --set-upstream origin main
}

#==============================================================================
# interactive menu
#==============================================================================

gi_flow_create() {
  local reconfigure="$1"
  local repo_name username name email

  read -rp "Enter the name for the new repository: " repo_name
  [[ -n "$repo_name" ]] || { echo "Repository name cannot be empty." >&2; return 1; }

  if (( ! reconfigure )); then
    username=$(gi_gh_user 2>/dev/null || true)
  fi
  [[ -n "${username:-}" ]] || read -rp "Enter your GitHub username: " username

  if (( ! reconfigure )); then
    name=$(git config --global user.name 2>/dev/null || true)
  fi
  [[ -n "${name:-}" ]] || read -rp "Enter your full name: " name

  if (( ! reconfigure )); then
    email=$(git config --global user.email 2>/dev/null || true)
  fi
  [[ -n "${email:-}" ]] || read -rp "Enter your email address: " email

  local full
  if full=$(gi_gh_new_repo "$repo_name"); then
    echo "Repository '$full' created successfully."
    gi_init_local_repo "$repo_name" "$username" "$name" "$email"
  fi
}

gi_flow_clone() {
  local repos
  mapfile -t repos < <(gi_gh_repos | sort)
  if [[ ${#repos[@]} -eq 0 ]]; then
    echo "No repositories found." >&2
    return 0
  fi

  echo "Select a repository to clone:"
  local i
  for i in "${!repos[@]}"; do
    echo "  $((i+1)). ${repos[i]}"
  done

  local selection selected
  while :; do
    read -rp "Enter repository number (1-${#repos[@]}): " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#repos[@]} )); then
      selected="${repos[selection-1]}"
      break
    fi
    echo "Invalid selection." >&2
  done

  local helper_arg
  helper_arg=$(gi_credential_helper_arg)

  git -c credential.helper="$helper_arg" clone "https://github.com/${selected}.git" || return 1

  local repo_name="${selected#*/}"
  if [[ -d "$repo_name" ]]; then
    cd "$repo_name" || return 1
    git config credential.helper "$helper_arg"
    git config remote.origin.url "https://github.com/${selected}.git"
    echo "Clone complete. Credential helper configured."
  fi
}

gi_menu() {
  local reconfigure="${1:-0}"
  echo ""
  echo "What would you like to do?"
  echo "  [1] Create a new repository"
  echo "  [2] Clone an existing repository"
  echo "  [3] Continue to shell"
  local choice
  read -rp "Please select [1-3]: " choice
  case "$choice" in
    1) gi_flow_create "$reconfigure" ;;
    2) gi_flow_clone ;;
    3) echo "Continuing to shell..." ;;
    *) echo "Invalid choice." >&2; return 1 ;;
  esac
}

#==============================================================================
# entry point
#==============================================================================

gi_print_help() {
  cat <<EOF
git-init $GI_VERSION

Usage:
  source init.sh [--reload] [--reconfigure] [--no-menu]
  ./init.sh     [--reload] [--reconfigure]

Options:
  --reload        Force reload of API keys even if env vars are already set.
  --reconfigure   Re-prompt for git config (name, email, GitHub user) instead of
                  reading existing values.
  --no-menu       (sourced only) Set up keys/credential helper but skip the
                  interactive menu.
  -h, --help      Show this help.

Functions exposed when sourced:
  gi_load_keys [--only N1,N2] [--except N1,N2] [--quiet]
  gi_clear_keys [--all]
  gi_update_key <name> [new-value]
  gi_list_keys
  gi_get_secret <secret-id>
  gi_connect_bitwarden
  gi_get_bws_token
  gi_gh_user
  gi_gh_repos
  gi_gh_new_repo <name>
  gi_init_local_repo <repo> <gh-username> <full-name> <email>
  gi_menu
EOF
}

_gi_main_body() {
  set -euo pipefail

  local reconfigure=0 reload=0 no_menu=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reconfigure) reconfigure=1; shift ;;
      --reload)      reload=1; shift ;;
      --no-menu)     no_menu=1; shift ;;
      -h|--help)     gi_print_help; return 0 ;;
      *) echo "Unknown argument: $1" >&2; gi_print_help >&2; return 2 ;;
    esac
  done

  local cmd
  for cmd in bws bw jq curl git; do
    command -v "$cmd" &>/dev/null || { echo "Error: $cmd command not found." >&2; return 1; }
  done

  gi_load_config || return 1
  echo "Loaded configuration from $_GI_CONFIG_PATH."

  local should_load=0
  if (( reload )); then
    should_load=1
  else
    local ev
    while IFS= read -r ev; do
      [[ -n "$ev" ]] || continue
      if [[ -z "${!ev:-}" ]]; then
        should_load=1
        break
      fi
    done < <(echo "$_GI_CONFIG_JSON" | jq -r '.KeyMap[].Env | keys[]')
  fi

  if (( should_load )); then
    echo "Loading API Keys..."
    gi_load_keys || return 1
  else
    echo "API Keys already loaded. Use --reload to force reload."
  fi

  [[ -n "${GITHUB_ACCESS_TOKEN:-}" ]] \
    || { echo "GITHUB_ACCESS_TOKEN is not set after loading keys. Check your config's KeyMap." >&2; return 1; }

  gi_ensure_credential_helper

  if (( _GI_SOURCED && no_menu )); then
    return 0
  fi

  gi_menu "$reconfigure"
}

# Wrapper that always restores caller's shell options, even on failure paths.
_gi_main() {
  local _saved rc=0
  _saved="$(set +o)"
  _gi_main_body "$@" || rc=$?
  # Defensive: explicitly clear strict opts before eval, in case _saved is empty.
  set +e +u +o pipefail 2>/dev/null || true
  eval "$_saved"
  return "$rc"
}

if (( _GI_SOURCED )); then
  _gi_main "$@" || return $?
else
  _gi_main "$@"
fi

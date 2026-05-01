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
    return 1
  fi
  if [[ ! -s "$path" ]]; then
    echo "Config file is empty: $path" >&2
    return 1
  fi
  _GI_CONFIG_PATH="$path"
  _GI_CONFIG_JSON=$(cat "$path") || return 1
  # Require a JSON object (jq -e returns non-zero for null/empty/non-object).
  if ! printf '%s' "$_GI_CONFIG_JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "Config is not a JSON object: $path" >&2
    return 1
  fi
  return 0
}

gi_config_get() {
  # Usage: gi_config_get '<jq filter>'
  [[ -n "$_GI_CONFIG_JSON" ]] || gi_load_config || return 1
  echo "$_GI_CONFIG_JSON" | jq -r "$1"
}

gi_config_default_path() {
  if [[ -n "${GIT_INIT_CONFIG:-}" ]]; then
    echo "${GIT_INIT_CONFIG}"
  else
    echo "$HOME/.git-init.json"
  fi
}

# Persist the in-memory config JSON to disk.
# Usage: gi_config_write <json-content> [path]
# If <path> is omitted, uses $_GI_CONFIG_PATH or gi_config_default_path.
# Note: takes content as an argument (not stdin) so callers can use it
# without a pipeline, which would put the function in a subshell and
# lose the _GI_CONFIG_* assignments. Also: every command checks its
# return value explicitly — bash suppresses errexit for the entire call
# tree below an `||` operator, so we cannot rely on set -e here.
gi_config_write() {
  local content="${1:-}"
  local path="${2:-${_GI_CONFIG_PATH:-$(gi_config_default_path)}}"
  [[ -n "$content" ]] || { echo "gi_config_write: content required" >&2; return 1; }
  if ! printf '%s' "$content" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "Refusing to write invalid JSON to $path." >&2
    return 1
  fi
  if ! mkdir -p "$(dirname "$path")"; then
    echo "Failed to create directory for $path." >&2
    return 1
  fi
  local tmp
  if ! tmp=$(mktemp "$path.XXXXXX"); then
    echo "Failed to create temp file in $(dirname "$path")." >&2
    return 1
  fi
  # >| overrides the caller's `noclobber` setting; mktemp pre-creates the
  # file with 0600 perms so a plain `>` would otherwise fail with "cannot
  # overwrite existing file".
  if ! printf '%s\n' "$content" >| "$tmp"; then
    echo "Failed to write $tmp" >&2
    rm -f "$tmp"
    return 1
  fi
  chmod 600 "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$path"; then
    echo "Failed to move $tmp to $path" >&2
    rm -f "$tmp"
    return 1
  fi
  _GI_CONFIG_PATH="$path"
  _GI_CONFIG_JSON="$content"
  echo "Wrote $path" >&2
}

gi_config_show() {
  if [[ -z "$_GI_CONFIG_JSON" ]]; then
    gi_load_config 2>/dev/null || { echo "No config loaded." >&2; return 1; }
  fi
  echo "Path: $_GI_CONFIG_PATH" >&2
  echo "$_GI_CONFIG_JSON" | jq .
}

gi_config_init() {
  # Interactive bootstrap. Optional arg: target path.
  local target="${1:-}"
  [[ -z "$target" ]] && target=$(gi_config_default_path)

  if [[ -f "$target" ]]; then
    echo "Config already exists at $target. Use gi_config_add_key / gi_config_set to modify it." >&2
    return 1
  fi

  echo "Setting up a new git-init configuration at $target" >&2

  local item cli gh_id
  read -rp "Bitwarden vault item (name or UUID) holding the BWS access token [Bitwarden Secrets Manager Service Account]: " item
  item=${item:-Bitwarden Secrets Manager Service Account}

  read -rp "BWS CLI executable [bws]: " cli
  cli=${cli:-bws}

  echo "" >&2
  echo "Your KeyMap needs at least a 'GitHub' entry mapping to GITHUB_ACCESS_TOKEN." >&2
  echo "List BWS secrets with: bws secret list" >&2
  read -rp "GitHub PAT secret UUID in BWS (8-4-4-4-12 hex): " gh_id
  if [[ -z "$gh_id" ]]; then
    echo "GitHub secret UUID is required. Aborting." >&2
    return 1
  fi
  if ! _gi_is_uuid "$gh_id"; then
    echo "'$gh_id' is not a valid UUID (expected 8-4-4-4-12 hex chars). Aborting." >&2
    return 1
  fi

  local config
  config=$(jq -n \
    --arg item "$item" \
    --arg cli  "$cli" \
    --arg gh   "$gh_id" \
    '{
      BwsCliPath:   $cli,
      BwsTokenItem: $item,
      KeyMap: [
        { Name: "GitHub", SecretId: $gh, Env: { GITHUB_ACCESS_TOKEN: "$secret" } }
      ]
    }')
  gi_config_write "$config" "$target"
}

gi_config_set() {
  # gi_config_set <field> <value>  (field: BwsCliPath | BwsTokenItem)
  local field="${1:-}" value="${2:-}"
  [[ -n "$field" && -n "$value" ]] || { echo "Usage: gi_config_set <BwsCliPath|BwsTokenItem> <value>" >&2; return 1; }
  case "$field" in
    BwsCliPath|BwsTokenItem) ;;
    *) echo "Unknown field '$field'. Valid: BwsCliPath, BwsTokenItem." >&2; return 1 ;;
  esac

  if [[ -z "$_GI_CONFIG_JSON" ]]; then
    gi_load_config 2>/dev/null \
      || _GI_CONFIG_JSON=$(jq -n '{BwsCliPath:"bws", BwsTokenItem:"Bitwarden Secrets Manager Service Account", KeyMap: []}')
  fi
  local updated
  updated=$(printf '%s' "$_GI_CONFIG_JSON" | jq --arg f "$field" --arg v "$value" '.[$f] = $v')
  gi_config_write "$updated"
  echo "Set $field = $value" >&2
}

gi_config_add_key() {
  # gi_config_add_key [name] [secret-id] [env-var | env-var=value] [...]
  # Prompts for any missing required argument. If only the env name is given,
  # the value defaults to "$secret" (which gets replaced with the BWS value at load time).
  local name="${1:-}" secret_id="${2:-}"
  [[ $# -ge 1 ]] && shift
  [[ $# -ge 1 ]] && shift

  if [[ -z "$name" ]]; then
    read -rp "Key name (e.g. GitHub, OpenAI): " name
  fi
  [[ -n "$name" ]] || { echo "Name is required." >&2; return 1; }

  if [[ -z "$secret_id" ]]; then
    read -rp "BWS secret UUID for '$name' (8-4-4-4-12 hex): " secret_id
  fi
  [[ -n "$secret_id" ]] || { echo "SecretId is required." >&2; return 1; }
  if ! _gi_is_uuid "$secret_id"; then
    echo "'$secret_id' is not a valid UUID." >&2
    return 1
  fi

  local env_specs=("$@")
  if [[ ${#env_specs[@]} -eq 0 ]]; then
    local default_var
    case "$name" in
      [Gg]it[Hh]ub)        default_var="GITHUB_ACCESS_TOKEN" ;;
      [Oo]pen[Aa][Ii])     default_var="OPENAI_API_KEY" ;;
      [Aa]nthropic)        default_var="ANTHROPIC_API_KEY" ;;
      *)                   default_var="$(echo "$name" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')_API_KEY" ;;
    esac
    local var
    read -rp "Environment variable name [$default_var]: " var
    env_specs=("${var:-$default_var}")
  fi

  local env_json='{}' pair key val
  for pair in "${env_specs[@]}"; do
    if [[ "$pair" == *=* ]]; then
      key="${pair%%=*}"
      val="${pair#*=}"
    else
      key="$pair"
      val='$secret'
    fi
    env_json=$(echo "$env_json" | jq --arg k "$key" --arg v "$val" '. + {($k): $v}')
  done

  if [[ -z "$_GI_CONFIG_JSON" ]]; then
    gi_load_config 2>/dev/null \
      || _GI_CONFIG_JSON=$(jq -n '{BwsCliPath:"bws", BwsTokenItem:"Bitwarden Secrets Manager Service Account", KeyMap: []}')
  fi

  local updated
  updated=$(printf '%s' "$_GI_CONFIG_JSON" | jq \
    --arg name "$name" \
    --arg sid  "$secret_id" \
    --argjson env "$env_json" '
      .KeyMap = (
        (.KeyMap // []) | map(select(.Name != $name)) +
        [{ Name: $name, SecretId: $sid, Env: $env }]
      )
    ')
  gi_config_write "$updated"
  echo "Added/updated '$name' in $_GI_CONFIG_PATH." >&2
}

gi_config_remove_key() {
  local name="${1:-}"
  [[ -n "$name" ]] || { echo "Usage: gi_config_remove_key <name>" >&2; return 1; }
  [[ -n "$_GI_CONFIG_JSON" ]] || gi_load_config || return 1

  local updated
  updated=$(printf '%s' "$_GI_CONFIG_JSON" \
    | jq --arg n "$name" '.KeyMap = (.KeyMap | map(select(.Name != $n)))')
  gi_config_write "$updated"
  echo "Removed '$name'." >&2
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
  local out rc
  out=$(_gi_bws secret get "$id" -o json 2>&1)
  rc=$?
  if (( rc != 0 )); then
    # Surface the bws CLI error so callers can show why a fetch failed
    # (e.g. "404 Not Found", "bws is not authenticated").
    printf '  bws: %s\n' "${out:-<no output>}" >&2
    return 1
  fi
  printf '%s' "$out" | jq -r '.value'
}

_gi_is_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
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

  Key loading / management:
    gi_load_keys [--only N1,N2] [--except N1,N2] [--quiet]
    gi_clear_keys [--all]
    gi_update_key <name> [new-value]
    gi_list_keys
    gi_get_secret <secret-id>

  Config management (no JSON editing required):
    gi_config_init [path]
    gi_config_show
    gi_config_set <BwsCliPath|BwsTokenItem> <value>
    gi_config_add_key [name] [secret-id] [VAR | VAR=value] [...]
    gi_config_remove_key <name>

  Bitwarden / GitHub helpers:
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

  local bootstrapped=0
  if ! gi_load_config 2>/dev/null; then
    echo "No git-init config found at \$GIT_INIT_CONFIG / ~/.git-init.json / $(gi_script_dir)/config.json."
    echo "Let's set one up."
    if ! gi_config_init; then
      echo "Bootstrap aborted." >&2
      return 1
    fi
    bootstrapped=1
    # gi_config_init already populated _GI_CONFIG_JSON / _GI_CONFIG_PATH
    # in-memory; no need to re-read from disk.
  fi
  echo "Loaded configuration from $_GI_CONFIG_PATH."

  # Sanity check: the KeyMap must contain at least one entry, otherwise
  # we can't load anything.
  local keymap_size
  keymap_size=$(printf '%s' "$_GI_CONFIG_JSON" | jq '.KeyMap | length // 0')
  if [[ "$keymap_size" -eq 0 ]]; then
    echo "KeyMap in $_GI_CONFIG_PATH is empty." >&2
    echo "Add an entry with: gi_config_add_key <name> <bws-secret-uuid> <ENV_VAR>" >&2
    return 1
  fi

  local should_load=0
  if (( reload || bootstrapped )); then
    should_load=1
  else
    local ev
    while IFS= read -r ev; do
      [[ -n "$ev" ]] || continue
      if [[ -z "${!ev:-}" ]]; then
        should_load=1
        break
      fi
    done < <(printf '%s' "$_GI_CONFIG_JSON" | jq -r '.KeyMap[].Env | keys[]')
  fi

  if (( should_load )); then
    echo "Loading API Keys..."
    if ! gi_load_keys; then
      echo "" >&2
      echo "Some keys failed to load. Common fixes:" >&2
      echo "  - Verify the SecretId with: bws secret list" >&2
      echo "  - Update an entry:           gi_config_add_key <name> <correct-uuid> <ENV_VAR>" >&2
      echo "  - Remove a bad entry:        gi_config_remove_key <name>" >&2
      echo "  - Show current config:       gi_config_show" >&2
      return 1
    fi
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
# Note: don't use $(set +o) — bash clears -e inside command-substitution subshells
# (non-POSIX behavior), which would make us "restore" errexit-off when the caller
# actually had errexit on. Inspect $- and shopt -qo directly instead.
_gi_main() {
  local _e=0 _u=0 _p=0 rc=0
  [[ $- == *e* ]] && _e=1
  [[ $- == *u* ]] && _u=1
  shopt -qo pipefail 2>/dev/null && _p=1

  _gi_main_body "$@" || rc=$?

  set +e +u +o pipefail 2>/dev/null || true
  (( _e )) && set -e
  (( _u )) && set -u
  (( _p )) && set -o pipefail
  return "$rc"
}

if (( _GI_SOURCED )); then
  _gi_main "$@" || return $?
else
  _gi_main "$@"
fi

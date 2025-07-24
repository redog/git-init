#!/usr/bin/env bash

MYINIT="git-init"
choice=-1

# Determine if the script was sourced or executed
sourced=0
[[ ${BASH_SOURCE[0]} != "$0" ]] && sourced=1

# Exit or return based on invocation
safe_exit() {
  local code=${1:-0}
  if (( sourced )); then
    return "$code"
  else
    exit "$code"
  fi
}

# Print an error message then exit/return with the given status
fail() {
  local code=${1:-1}
  shift
  [[ $# -gt 0 ]] && echo "$*" >&2
  safe_exit "$code"
}

choose() {
  options=("$@")
  for i in "${!options[@]}"; do
    echo "[$i] ${options[i]}" >&2
  done

  while true; do
    read -p "Please select: " choice
    if [[ $choice =~ ^[0-9]+$ ]] && [[ $choice -ge 0 ]] && [[ $choice -lt ${#options[@]} ]]; then
      echo "${options[$choice]}"
      return
    else
      echo "That was not a valid choice!" >&2
    fi
  done
}

get_repositories() {
  token="$1"
#  username="$2"
  if ! response=$(curl -H "Authorization: token ${token}" "https://api.github.com/user/repos" 2>&1); then
    echo "Failed to fetch repositories." >&2
    safe_exit 3
  fi
  echo "$response" | grep -o '"full_name":\s*"[^"]*"' | sed -E 's/"full_name":[[:space:]]*"([^"]*)"/\1/'
}

main() {
  if (( sourced )); then
    saved_opts="$(set +o)"
  fi
  set -euo pipefail

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  # Load configuration for secret IDs
  if [[ -n "${GIT_INIT_CONFIG:-}" && -f "${GIT_INIT_CONFIG}" ]]; then
    source "${GIT_INIT_CONFIG}"
  elif [[ -f "$HOME/.git-init.env" ]]; then
    source "$HOME/.git-init.env"
  elif [[ -f "${SCRIPT_DIR}/config.env" ]]; then
    source "${SCRIPT_DIR}/config.env"
  else
    echo "Warning: config.env file not found." >&2
  fi

  # Ensure required commands exist
  for cmd in bws bw jq curl git; do
    if ! command -v "$cmd" &>/dev/null; then
      fail 1 "Error: $cmd command not found."
    fi
  done

  helper_script="${HOME}/.config/git-credential-env"
  if [[ ! -f $helper_script ]]; then
    mkdir -p "${HOME}/.config"
    cat >"$helper_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
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
    chmod +x "$helper_script"
  fi

  ensure_logged_in() {
    local status
    status=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null)
    if [[ "$status" == "unauthenticated" || -z "$status" ]]; then
      if [[ -z "${BW_CLIENTSECRET:-}" ]]; then
        read -s -p "Enter BW client secret (leave blank for email/password login): " BW_CLIENTSECRET
        echo
      fi
      if [[ -n "${BW_CLIENTSECRET:-}" && -n "${BW_CLIENTID:-}" ]]; then
        echo "🔑 Logging in to Bitwarden CLI using API key..."
        BW_CLIENTSECRET="$BW_CLIENTSECRET" bw login --apikey
      else
        echo "🔑 Logging in to Bitwarden CLI..."
        bw login
      fi
      unset BW_SESSION
      ensure_session
    fi
  }

  ensure_session() {
    if [[ -n "${BW_SESSION:-}" ]]; then
      echo "✅ Vault is already unlocked."
      return 0
    fi

    local status
    status=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null)
    if [[ "$status" == "unauthenticated" || -z "$status" ]]; then
      ensure_logged_in || return 1
      status=$(bw status 2>/dev/null | jq -r '.status' 2>/dev/null)
      if [[ "$status" == "unauthenticated" || -z "$status" ]]; then
        echo "❌ Bitwarden CLI login failed." >&2
        return 1
      fi
    fi

    echo "🔐 Unlocking Bitwarden vault... please enter your master password:"
    local session
    session=$(bw unlock --raw)
    if [[ $? -ne 0 || -z "$session" || "$session" == "You are not logged in."* ]]; then
      echo "❌ Unlock failed. Please check your password." >&2
      return 1
    fi
    export BW_SESSION="$session"
    echo "✅ Vault unlocked successfully. Session key is now in your environment."
  }

  ensure_logged_in
  if ! ensure_session; then
    fail 1 "Failed to unlock Bitwarden vault"
  fi

  # Retrieve BWS access token if missing
  if [[ -z "${BWS_ACCESS_TOKEN:-}" ]]; then
    echo "=> Retrieving BWS access token from Bitwarden..."
    BWS_ACCESS_TOKEN=$(bw get password "$BWS_ACCESS_TOKEN_ID" --session "$BW_SESSION" 2>/dev/null)
    if [[ -z "$BWS_ACCESS_TOKEN" ]]; then
      fail 1 "Failed to retrieve BWS access token"
    fi
    export BWS_ACCESS_TOKEN
  fi

  secret_data=$(bws secret get "$BW_API_KEY_ID" -o json 2>/dev/null)
  if [[ $? -ne 0 || -z "$secret_data" ]]; then
    fail 1 "Failed to retrieve secret with ID '$BW_API_KEY_ID'"
  fi

  BW_CLIENTSECRET=$(echo "$secret_data" | jq -r '.value')
  if [[ -z "$BW_CLIENTSECRET" ]]; then
    fail 1 "Could not extract client_secret from the secret data"
  fi

  ensure_logged_in
  export BW_CLIENTID BW_CLIENTSECRET

  # Fetch GitHub token using Bitwarden Secrets Manager
  if [[ "$OSTYPE" == "darwin"* || "$OSTYPE" == "linux-gnu"* ]]; then
    if ! pass=$(bws secret get "$GH_TOKEN_ID" -o json | jq -r '.value' 2>/dev/null); then
      fail 1 "Failed to retrieve GitHub access token"
    fi
  elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    fail 4 "Windows not yet supported"
  else
    fail 5 "Unsupported OS"
  fi

  gitusername=$(git config --global user.github.login.name || true)
  if [[ -z "$gitusername" ]]; then
    read -p "Enter your GitHub username: " gitusername
    git config --global user.github.login.name "$gitusername"
  fi

  email=$(git config --global user.email || echo "${gitusername}@users.noreply.github.com")
  if [[ -z "$(git config --global user.email || true)" ]]; then
    read -p "Enter your email [${gitusername}@users.noreply.github.com]: " email
    email=${email:-"${gitusername}@users.noreply.github.com"}
    git config --global user.email "$email"
  fi

  name=$(git config --global user.name || true)
  if [[ -z "$name" ]]; then
    read -p "Enter your Full Name: " name
    git config --global user.name "$name"
  fi

  export GITHUB_ACCESS_TOKEN="$pass"
  if [[ -z "$GITHUB_ACCESS_TOKEN" ]]; then
    fail 6 "GitHub Access Token not set"
  fi

  echo ""
  echo "What would you like to do?"
  choose "Create a new repository" "Clone an existing repository"

  if [[ $choice -eq 0 ]]; then
    # Check if we're inside a git repository
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "Script is running from within a git repository.  Further cloning is not recommended."
      echo "Please run this script from outside of a git repository."
      fail 1
    elif [[ -z "$SCRIPT_DIR" || "$SCRIPT_DIR" == "." ]]; then
      git clone https://github.com/$gitusername/${MYINIT}
    else
      if [[ ! -d "$MYINIT" ]]; then
        git clone https://github.com/$gitusername/${MYINIT} "$MYINIT"
      fi
    fi

    bash ${MYINIT}/mkrepo.sh
  else
    repos=$(get_repositories "${GITHUB_ACCESS_TOKEN}")
    if [[ -z "$repos" ]]; then
      echo "No repositories found." >&2
      safe_exit 0
    fi
    repo_array=()
    while IFS= read -r line; do
      repo_array+=("$line")
    done <<< "$repos"

    chosen_repo=$(choose "${repo_array[@]}")
    helper_script="${HOME}/.config/git-credential-env"
    git -c credential.helper="$helper_script" clone "https://github.com/${chosen_repo}.git"
    cd "${chosen_repo#*/}" || fail 1
    case "$OSTYPE" in
      darwin*) git config credential.helper osxkeychain ;;
      linux*)  git config credential.helper "$helper_script" ;;
      msys*|cygwin*) git config credential.helper manager ;;
      *) echo "Unsupported OS for credential helper config." ;;
    esac

    git config "remote.origin.url" "https://github.com/${chosen_repo}.git"
  fi

  unset IFS

  if (( sourced )); then
    eval "$saved_opts"
  fi
}

if (( sourced )); then
  main "$@" || return $?
else
  main "$@"
fi


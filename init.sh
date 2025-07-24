#!/usr/bin/env bash
set -euo pipefail

MYINIT="git-init"
choice=-1

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
    exit 3
  fi
  echo "$response" | grep -o '"full_name":\s*"[^"]*"' | sed -E 's/"full_name":[[:space:]]*"([^"]*)"/\1/'
}

if [[ -z $BWS_ACCESS_TOKEN ]]; then
  echo "Bitwarden Access Token not set check environment."
  exit 6
fi

# Attempt to retrieve the password
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  if ! pass=$(bws secret get "$GH_TOKEN_ID" -o json | jq -r '.value' 2>/dev/null); then
    echo "Failed to retrieve GitHub access token" >&2
    exit 1
  fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux
  if ! pass=$(bws secret get "$GH_TOKEN_ID" -o json | jq -r '.value' 2>/dev/null); then
    echo "Problem retrieving GitHub access token" >&2
    exit 2
  fi

elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  # Windows
  echo "Windows not yet supported"
  exit 4
else
  # Unknown OS
  echo "Unsupported OS"
  exit 5
fi

gitusername=$(git config --global user.github.login.name)

if [[ -z "$gitusername" ]]; then
  read -p "Enter your GitHub username: " gitusername
  git config --global user.github.login.name "$gitusername"
fi

email=$(git config --global user.email "$gitusername"@users.noreply.github.com)

name=$(git config --global user.name )

if [[ -z "$name" ]]; then
  read -p "Enter your Full Name: " name
  git config --global user.name "$name"
fi

export GITHUB_ACCESS_TOKEN="$pass"

if [[ -z $GITHUB_ACCESS_TOKEN ]]; then
  echo "GitHub Access Token not set check environment."
  exit 6
fi

echo ""
echo "What would you like to do?"
choose "Create a new repository" "Clone an existing repository"


if [[ $choice -eq 0 ]]; then
  # Determine the script's directory
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Check if we're inside a git repository
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Script is being run from within a git repo
    echo "Script is running from within a git repository.  Further cloning is not recommended."
    echo "Please run this script from outside of a git repository."
    exit 1
  elif [[ -z "$SCRIPT_DIR" || "$SCRIPT_DIR" == "." ]]; then
    git clone https://github.com/$gitusername/${MYINIT}
  else
    # Script is being run from the filesystem, but not within a git repo
    if [[ ! -d "$MYINIT" ]]; then
      git clone https://github.com/$gitusername/${MYINIT} "$MYINIT"
    fi
  fi

  if [[ -f "${MYINIT}/config.env" ]]; then
    source "${MYINIT}/config.env"
  else
    echo "Warning: config.env file not found." >&2
  fi

  bash ${MYINIT}/mkrepo.sh
else
  repos=$(get_repositories "${GITHUB_ACCESS_TOKEN}")
    if [[ -z "$repos" ]]; then
    echo "No repositories found." >&2
    exit 0
  fi
  repo_array=()
  while IFS= read -r line; do
    repo_array+=("$line")
  done <<< "$repos"

  chosen_repo=$(choose "${repo_array[@]}")
  # FIX: Use the access token in the clone URL to prevent password prompts for private repos.
  git clone "https://x-access-token:${GITHUB_ACCESS_TOKEN}@github.com/${chosen_repo}.git"
  cd "${chosen_repo#*/}" || exit 1
  # Configure git to use the credential manager.
  case "$OSTYPE" in
    darwin*) git config credential.helper osxkeychain ;;
    linux*)  git config credential.helper ${HOME}/.config/git-credential-env ;;
    msys*|cygwin*) git config credential.helper manager ;;
    *) echo "Unsupported OS for credential helper config." ;;
  esac
  
  git config "remote.origin.url" "https://github.com/${chosen_repo}.git"
fi

unset IFS

#!/usr/bin/env bash

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
  username="$2"
  response=$(curl -H "Authorization: token ${token}" "https://api.github.com/user/repos" 2>&1)
  if [[ $? -ne 0 ]]; then
    echo "Failed to fetch repositories."
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
  pass=$(bws secret get 857d0c2c-cfe0-4e6d-995c-b1690020f8fb -o tsv | tail -n 1 | awk '{print $3}' 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "Failed to retrieve GitHub access token"
    exit 1
  fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux
  pass=$(bws secret get 857d0c2c-cfe0-4e6d-995c-b1690020f8fb -o tsv | tail -n 1 | awk '{print $3}' 2>/dev/null)
  if [[ $? -ne 0  ]]; then
    echo "Problem retrieving GitHub access token"
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

gitusername=$(git config user.github.login.name)

if [[ $? -ne 0 ]]; then
  read -p "Enter your Github username: " gitusername
fi

export GITHUB_ACCESS_TOKEN="$pass"

if [[ -z $GITHUB_ACCESS_TOKEN ]]; then
  echo "Github Access Token not set check environment."
  exit 6
fi

echo ""
echo "What would you like to do?"
choose "Create a new repository" "Clone an existing repository"


if [[ $choice -eq 0 ]]; then
  # Determine the script's directory
  SCRIPT_DIR=$(dirname "$0")
  # Check if we're inside a git repository
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Script is being run from within a git repo
    echo "Script is running from within a git repository.  Further cloning is not recommended."
    echo "Please run this script from outside of a git repository."
    exit 1
  elif [[ -z "$SCRIPT_DIR" || "$SCRIPT_DIR" == "." ]]; then
    # Assuming curl execution or similar
    git clone https://github.com/$gitusername/${MYINIT}
  else
    # Script is being run from the filesystem, but not within a git repo
    git clone https://github.com/$gitusername/${MYINIT} "$MYINIT" # Clone into a directory named MYINIT
  fi

  python3 ${MYINIT}/mkrepo.py
else
  repos=$(get_repositories "${GITHUB_ACCESS_TOKEN}")
  IFS=$'\n' read -rd '' -a repo_array <<<"$repos"
  chosen_repo=$(choose ${repo_array[@]})
  git clone https://github.com/${chosen_repo}
  cd "${chosen_repo#*/}" || exit 1
  # Configure git to use the credential manager.
  git config credential.helper 'manager'
  git config "remote.origin.url" "https://github.com/${chosen_repo}.git"
fi

unset IFS

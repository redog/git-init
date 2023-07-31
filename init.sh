#!/bin/bash

MYINIT="git-init"

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
  curl -H "Authorization: token ${token}" "https://api.github.com/user/repos" 2>&1 | \
    grep -o '"full_name":\s*"[^"]*"' | \
    sed -E 's/"full_name":[[:space:]]*"([^"]*)"/\1/'
}

# Attempt to retrieve the password
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  pass=$(security find-generic-password -s 'github' -w 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "Failed to retrieve GitHub access token"
    exit 1
  fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux
  pass=$(secret-tool lookup github accesstoken 2>/dev/null)
  # Replace this with the actual command for Linux
  if [[ $? -ne 0  ]]; then
    echo "Problem retrieving GitHub access token"
    exit 1
  fi
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  # Windows
  # Replace this with the actual command for Windows
  echo "Windows not yet supported"
  exit 1
else
  # Unknown OS
  echo "Unsupported OS"
  exit 1
fi

gitusername=$(git config user.github.login.name)

if [[ $? -ne 0 ]]; then
  echo "Github login name not set. Configure with git. "
  exit 1
fi

export GITHUB_ACCESS_TOKEN="$pass"

echo ""
echo "What would you like to do?"
choose "Create a new repository" "Clone an existing repository"


if [[ $choice -eq 0 ]]; then
  python3 ${MYINIT}/mkrepo.py
else 
  repos=$(get_repositories "${GITHUB_ACCESS_TOKEN}")
  IFS=$'\n' read -rd '' -a repo_array <<<"$repos"
  chosen_repo=$(choose ${repo_array[@]})
  git clone https://github.com/${chosen_repo}
  git -C "./${chosen_repo#*/}" config "user.github.token" "${pass}"
  git -C "./${chosen_repo#*/}" config "remote.origin.url" "https://${gitusername}:${pass}@github.com/${githubusername}${chosen_repo}"
#python3 ${MYINIT}/mkrepo.py
fi

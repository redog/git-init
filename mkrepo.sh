#!/usr/bin/env bash
set -euo pipefail

# Consolidated script to create a GitHub repository and initialize it locally.

# Function to prompt for user input if not already set in git config
get_user_input() {
  local prompt_message=$1
  local config_key=$2
  local validation_regex=$3
  local error_message=$4
  local current_value
  current_value=$(git config --global "$config_key" || true)

  if [[ -z "$current_value" ]]; then
    while true; do
      read -rp "$prompt_message: " new_value
      if [[ -n "$new_value" ]]; then
        if [[ -n "$validation_regex" && ! "$new_value" =~ $validation_regex ]]; then
          echo "$error_message" >&2
        else
          git config --global "$config_key" "$new_value"
          echo "$new_value"
          break
        fi
      else
        echo "Input cannot be empty. Please try again." >&2
      fi
    done
  else
    echo "$current_value"
  fi
}

# Function to create a repository on GitHub
create_github_repo() {
  local repo_name=$1
  local token=$2
  local api_url="https://api.github.com/user/repos"
  local post_data
  post_data=$(printf '{"name":"%s","description":"Created with the GitHub API","private":true}' "$repo_name")
  local response
  response=$(curl -fsSL -w "%{http_code}" -H "Authorization: token $token" \
    -H "Accept: application/vnd.github.v3+json" \
    -d "$post_data" "$api_url")
  local status="${response: -3}"
  local body="${response::-3}"
  if [[ "$status" != "201" ]]; then
    echo "Failed to create repository: HTTP $status" >&2
    [[ -n "$body" ]] && echo "$body" >&2
    exit 1
  fi
  echo "Successfully created repository \"$repo_name\""
}

# Function to initialize a local git repository
initialize_local_repo() {
  local repo_name=$1
  local username=$2
  local token=$3

  if [[ -d "$repo_name" ]]; then
    echo "Directory ${repo_name} already exists" >&2
    exit 1
  fi

  mkdir "$repo_name" || { echo "Failed to create directory ${repo_name}" >&2; exit 1; }
  cd "$repo_name"

  git init
  if [[ -z $(git config --global --get credential.helper) ]]; then
    git config --global credential.helper "!${HOME}/.config/git-credential-env"
  fi
  if [[ -z $(git config --global --get push.default) ]]; then
    git config --global push.default simple
  fi

  local repo_exists
  repo_exists=$(curl -fsSL -H "Authorization: token ${token}" "https://api.github.com/repos/${username}/${repo_name}")
  if [[ -z ${repo_exists} ]]; then
    echo "GitHub repo ${username}/${repo_name} does not exist" >&2
    exit 1
  fi

  git remote add origin "https://github.com/${username}/${repo_name}.git"

  echo  "${repo_name} by ${username}" > README.md
  curl https://www.gnu.org/licenses/gpl-3.0.txt > LICENSE

  git add .
  git commit -m "Initial commit"
  git branch -M main
  git push --set-upstream origin main
}

main() {
  # Get details from global git config or prompt the user
  local name
  name=$(get_user_input "Full Name" "user.name" "" "Full name cannot be empty.")
  local email
  email=$(get_user_input "Email Address" "user.email" "^[^@]+@[^@]+\.[^@]+$" "Invalid email address.")
  local username
  username=$(get_user_input "GitHub username" "user.github.login.name" "" "GitHub username cannot be empty.")

  # Repository name
  local repo
  while true; do
    read -rp "Enter a unique name for the new repo: " repo
    [[ -n "$repo" ]] && break
    echo "Repo name cannot be empty. Please try again." >&2
  done

  # GitHub token from environment
  if [[ -z "${GITHUB_ACCESS_TOKEN:-}" ]]; then
    echo "The GITHUB_ACCESS_TOKEN environment variable is not set." >&2
    exit 1
  fi
  local token="$GITHUB_ACCESS_TOKEN"

  create_github_repo "$repo" "$token"
  initialize_local_repo "$repo" "$username" "$token"
}

main "$@"

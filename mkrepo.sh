#!/usr/bin/env bash
set -euo pipefail

# Consolidated script to create a GitHub repository and initialize it locally.

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get details from global git config or prompt the user
name=$(git config --global user.name || true)
if [[ -z "$name" ]]; then
  while true; do
    read -rp "Full Name: " name
    [[ -n "$name" ]] && break
    echo "Full name cannot be empty. Please try again." >&2
  done
fi

email=$(git config --global user.email || true)
if [[ -z "$email" ]]; then
  while true; do
    read -rp "Email Address: " email
    if [[ "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
      break
    fi
    echo "Invalid email address. Please try again." >&2
  done
fi

username=$(git config --global user.github.login.name || true)
if [[ -z "$username" ]]; then
  while true; do
    read -rp "GitHub username: " username
    [[ -n "$username" ]] && break
    echo "GitHub username cannot be empty. Please try again." >&2
  done
fi

# Repository name
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
token="$GITHUB_ACCESS_TOKEN"

# Create repository via GitHub API
api_url="https://api.github.com/user/repos"
post_data=$(printf '{"name":"%s","description":"Created with the GitHub API","private":true}' "$repo")
response=$(curl -fsSL -w "%{http_code}" -H "Authorization: token $token" \
  -H "Accept: application/vnd.github.v3+json" \
  -d "$post_data" "$api_url")
status="${response: -3}"
body="${response::-3}"
if [[ "$status" != "201" ]]; then
  echo "Failed to create repository: HTTP $status" >&2
  [[ -n "$body" ]] && echo "$body" >&2
  exit 1
fi

echo "Successfully created repository \"$repo\""

# === Local repository setup ===
if [[ -d "$repo" ]]; then
  echo "Directory ${repo} already exists" >&2
  exit 1
fi

mkdir "$repo" || { echo "Failed to create directory ${repo}" >&2; exit 1; }
cd "$repo"

git init
if [[ -z $(git config --global --get user.name) ]]; then
  git config user.name "$name"
fi
if [[ -z $(git config --global --get user.email) ]]; then
  git config user.email "$email"
fi
if [[ -z $(git config --global --get user.github.login.name) ]]; then
  git config user.github.login.name "$username"
fi
if [[ -z $(git config --global --get credential.helper) ]]; then
  git config --global credential.helper "!${HOME}/.config/git-credential-env"
fi
if [[ -z $(git config --global --get push.default) ]]; then
  git config --global push.default simple
fi

repo_exists=$(curl -fsSL -H "Authorization: token ${token}" "https://api.github.com/repos/${username}/${repo}")
if [[ -z ${repo_exists} ]]; then
  echo "GitHub repo ${username}/${repo} does not exist" >&2
  exit 1
fi

git remote add origin "https://github.com/${username}/${repo}.git"

echo  "${repo} by ${username}" > README.md
curl https://www.gnu.org/licenses/gpl-3.0.txt > LICENSE

git add .
git commit -m "Initial commit"
git branch -M main
git push --set-upstream origin main

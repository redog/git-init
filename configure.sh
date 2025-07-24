#!/bin/bash

if [[ $# -ne 5 ]]; then
  echo "Usage: $0 <name> <email> <username> <token> <repo>"
  exit 1
fi

name=$1
email=$2
username=$3
token=$4
repo=$5

if [[ -d "${repo}" ]]; then
  echo "Directory ${repo} already exists"
  exit 1
fi

mkdir "${repo}"
if [[ $? -ne 0 ]]; then
  echo "Failed to create directory ${repo}"
  exit 1
fi

cd "${repo}"
git init
# Set user.name locally if it's not set globally
if [[ -z $(git config --global --get user.name) ]]; then
  git config user.name "${name}"
fi

# Set user.email locally if it's not set globally
if [[ -z $(git config --global --get user.email) ]]; then
  git config user.email "${email}"
fi

# Set user.github.login.name locally if it's not set globally
if [[ -z $(git config --global --get user.github.login.name) ]]; then
  git config user.github.login.name "${username}"
fi

# Set credential.helper globally if it's not set yet
if [[ -z $(git config --global --get credential.helper) ]]; then
  git config --global credential.helper "!${HOME}/.config/git-credential-env"
fi

# Set push.default globally if it's not set yet
if [[ -z $(git config --global --get push.default) ]]; then
  git config --global push.default simple
fi

# Verify the GitHub repo exists before trying to add it as a remote
repo_exists=$(curl -fsSL -H "Authorization: token ${token}" "https://api.github.com/repos/${username}/${repo}")

if [[ -z ${repo_exists} ]]; then
  echo "GitHub repo ${username}/${repo} does not exist"
  exit 1
fi

git remote add origin "https://github.com/${username}/${repo}.git"
echo  "${repo} by ${username}" > README.md 
curl https://www.gnu.org/licenses/gpl-3.0.txt > LICENSE
git add .
git commit -m "Initial commit"
git branch -M main 
git push --set-upstream origin main

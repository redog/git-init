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

git config user.name "${name}"
git config user.email "${email}"
git config user.github.login.name "${username}"
git config user.github.token "${token}"
git config credential.helper 'cache --timeout=1800'
git config push.default simple

# Verify the GitHub repo exists before trying to add it as a remote
repo_exists=$(curl -fsSL -H "Authorization: token ${token}" "https://api.github.com/repos/${username}/${repo}")

if [[ -z ${repo_exists} ]]; then
  echo "GitHub repo ${username}/${repo} does not exist"
  exit 1
fi

git remote add origin "https://${token}@github.com/${username}/${repo}.git"
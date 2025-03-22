#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Function to validate inputs
validate_input() {
    local input="$1"
    local pattern="^[a-zA-Z0-9@._-]+$"
    if [[ ! $input =~ $pattern ]]; then
        echo "Invalid input: $input"
        return 1
    fi
    return 0
}

# Function to configure git
configure_git() {
    local config_name="$1"
    local config_value="$2"
    local scope="$3"  # local or global

    # Validate inputs before using them
    if ! validate_input "$config_value"; then
        echo "Invalid configuration value for $config_name"
        return 1
    fi

    if [[ "$scope" == "global" ]]; then
        git config --global "$config_name" "$config_value"
    else
        git config "$config_name" "$config_value"
    fi
}

# Validate number of arguments
if [[ $# -ne 5 ]]; then
    echo "Usage: $0 <name> <email> <username> <token> <repo>"
    exit 1
fi

# Assign arguments to named variables
name="$(echo "$1" | tr -d '[:space:]')" # Trim spaces
email="$(echo "$2" | tr -d '[:space:]')" # Trim spaces
username="$(echo "$3" | tr -d '[:space:]')" # Trim spaces
token="$4"
repo="$5"

# Validate all inputs
for input in "$name" "$email" "$username" "$repo"; do
    if ! validate_input "$input"; then
        exit 1
    fi
done

# Create directory
if [[ -d "${repo}" ]]; then
    echo "Directory ${repo} already exists"
    exit 1
fi

mkdir -p "${repo}"
cd "${repo}" || exit 1

# Initialize git repository
git init

# Configure git settings
if [[ -z $(git config --global --get user.name) ]]; then
    configure_git "user.name" "${name}" "local"
fi

if [[ -z $(git config --global --get user.email) ]]; then
    configure_git "user.email" "${email}" "local"
fi

# Use git credential store
if [[ -n "${token}" ]]; then
    # Store credentials in OS credential manager
    if command -v git-credential-manager &> /dev/null; then
        echo "url=https://github.com
protocol=https
username=${username}
password=${token}" | git credential-manager store
    else
        # Fallback to cache with short timeout
        git config --global credential.helper 'cache --timeout=300'
        echo "Warning: git-credential-manager not found, using cache with 5-minute timeout"
    fi
fi

# Set push default if not set
if [[ -z $(git config --global --get push.default) ]]; then
    configure_git "push.default" "simple" "global"
fi

# Verify repo exists
repo_exists=$(curl -sS -H "Authorization: token ${token}" \
    "https://api.github.com/repos/${username}/${repo}")

if ! echo "${repo_exists}" | grep -q '"id":'; then
    echo "GitHub repo ${username}/${repo} does not exist"
    exit 1
fi

# Add remote using https protocol
git remote add origin "https://github.com/${username}/${repo}.git"

# Initialize repository
echo "# ${repo}" > README.md
curl -sS https://www.gnu.org/licenses/gpl-3.0.txt > LICENSE
git add .
git commit -m "Initial commit"
git branch -M main

# Push using stored credentials
GIT_ASKPASS=echo git push --set-upstream origin main

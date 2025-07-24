#!/bin/bash

# Helper to exit or return based on how the script was invoked
fail() {
    echo "❌ Failed to load secret" >&2
    (return 0 2>/dev/null) && return 1 || exit 1
}

# Determine the directory of this script so we can reliably load the config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Loads the Bitwarden API Key into environment variables from secrets manager.
if [[ -f "$SCRIPT_DIR/config.env" ]]; then
  source "$SCRIPT_DIR/config.env"
else
  echo "Warning: config.env file not found." >&2
fi

# Secret IDs from config
#BW_API_KEY_ID
#BWS_ACCESS_TOKEN_ID
#BW_CLIENT_ID

# Check if bws is installed.
if ! command -v bws &> /dev/null; then
  echo "Error: bws command not found.  Please install the Bitwarden Secrets Manager CLI." >&2
  fail 1
fi

# Check if bw is installed.
if ! command -v bw &> /dev/null; then
  echo "Error: bw command not found.  Please install the Bitwarden CLI." >&2
  fail 1
fi

# Check if jq is installed.
if ! command -v jq &> /dev/null; then
  echo "Error: jq command not found.  Please install jq." >&2
  fail 1
fi

# Function to ensure BW_SESSION is set and unlocked
ensure_session() {
  if [ -n "$BW_SESSION" ]; then
    echo "✅ Vault is already unlocked."
    return 0 # Use 'return' so sourcing doesn't exit the terminal
  fi

  echo "🔐 Unlocking Bitwarden vault... please enter your master password:"

  # Prompt for password, get the raw session key, and export it
  export BW_SESSION=$(bw unlock --raw)

  # Check if the unlock command was successful
  if [ $? -eq 0 ]; then
    echo "✅ Vault unlocked successfully. Session key is now in your environment."
  else
    echo "❌ Unlock failed. Please check your password."
    # Unset the variable in case of failure
    unset BW_SESSION
  fi
}

if ! ensure_session; then
  fail 1
fi

# If BWS_ACCESS_TOKEN isn't set, try retrieving it using bw
if [[ -z "$BWS_ACCESS_TOKEN" ]]; then
  echo "=> Retrieving BWS access token from Bitwarden..."
  BWS_ACCESS_TOKEN=$(bw get password "$BWS_ACCESS_TOKEN_ID" --session "$BW_SESSION" 2>/dev/null)
  if [[ -z "$BWS_ACCESS_TOKEN" ]]; then
    echo "Error: Failed to retrieve BWS access token." >&2
    fail 1
  fi
  export BWS_ACCESS_TOKEN
fi

# Retrieve the secret data as JSON.
secret_data=$(bws secret get "$BW_API_KEY_ID" -o json 2> /dev/null)

# Check if the secret retrieval was successful
if [ $? -ne 0 ]; then
  echo "Error: Failed to retrieve secret with ID '$BW_API_KEY_ID'."
  fail 1
fi
#Check if secret_data is empty
if [ -z "$secret_data" ]; then
    echo "Error: retrieved empty secret"
    fail 1
fi


BW_CLIENT_SECRET=$(echo "$secret_data" | jq -r '.value')

# Check if the variables were populated.
if [ -z "$BW_CLIENT_SECRET" ]; then
  echo "Error: Could not extract client_secret from the secret data.  Check the field names in your secret."
  fail 1
fi
export BW_CLIENT_ID BW_CLIENT_SECRET

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
SECRET_ID="$BW_API_KEY_ID"
BWS_TOKEN_ITEM_ID="$BWS_ACCESS_TOKEN_ID"

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
  if [[ -z "$BW_SESSION" ]] || ! bw status --session "$BW_SESSION" | grep -iq "unlocked"; then
    echo "=> Unlocking Bitwarden..."
    local session_output
    session_output=$(bw unlock --raw 2>/dev/null)
    if [ $? -ne 0 ]; then
      echo "Error: bw unlock failed." >&2
      fail 1
    fi
    if echo "$session_output" | grep -q "You are not logged in"; then
      echo "=> Logging into Bitwarden..."
      bw login --apikey --clientid "$BW_CLIENTID" --clientsecret "$BW_CLIENTSECRET"
      if [ $? -ne 0 ]; then
        echo "Error: bw login failed." >&2
        fail 1
      fi
      session_output=$(bw unlock --raw 2>/dev/null)
      if [ $? -ne 0 ]; then
        echo "Error: bw unlock failed." >&2
        fail 1
      fi
    fi
    if [[ -z "$session_output" ]] || ! bw status --session "$session_output" | grep -iq "unlocked"; then
      echo "Error: Failed to unlock Bitwarden." >&2
      return 1
    fi
    export BW_SESSION="$session_output"
  fi
}

if ! ensure_session; then
  fail 1
fi

# If BWS_ACCESS_TOKEN isn't set, try retrieving it using bw
if [[ -z "$BWS_ACCESS_TOKEN" ]]; then
  if [[ -z "$BWS_TOKEN_ITEM_ID" ]]; then
    echo "Error: BWS_ACCESS_TOKEN is not set and BWS_ACCESS_TOKEN_ID is unknown." >&2
    fail 1
  fi
  echo "=> Retrieving BWS access token from Bitwarden..."
  BWS_ACCESS_TOKEN=$(bw get password "$BWS_TOKEN_ITEM_ID" --session "$BW_SESSION" 2>/dev/null)
  if [[ -z "$BWS_ACCESS_TOKEN" ]]; then
    echo "Error: Failed to retrieve BWS access token." >&2
    fail 1
  fi
  export BWS_ACCESS_TOKEN
fi

# Retrieve the secret data as JSON.
secret_data=$(bws secret get "$SECRET_ID" -o json 2> /dev/null)

# Check if the secret retrieval was successful
if [ $? -ne 0 ]; then
  echo "Error: Failed to retrieve secret with ID '$SECRET_ID'."
  fail 1
fi
#Check if secret_data is empty
if [ -z "$secret_data" ]; then
    echo "Error: retrieved empty secret"
    fail 1
fi


BW_CLIENTID=$(echo "$secret_data" | jq -r '.client_id')
BW_CLIENTSECRET=$(echo "$secret_data" | jq -r '.client_secret')

# Check if the variables were populated.
if [ -z "$BW_CLIENTID" ] || [ -z "$BW_CLIENTSECRET" ]; then
  echo "Error: Could not extract client_id or client_secret from the secret data.  Check the field names in your secret."
  fail 1
fi
export BW_CLIENTID BW_CLIENTSECRET

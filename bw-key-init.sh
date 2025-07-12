#!/bin/bash

# Loads the Bitwarden API Key into environment variables from secrets manager.
if [[ -f "config.env" ]]; then
  source "config.env"
else
  echo "Warning: config.env file not found." >&2
fi
# Secret ID
SECRET_ID="$BW_API_KEY_ID"

# Check if bws is installed.
if ! command -v bws &> /dev/null; then
  echo "Error: bws command not found.  Please install the Bitwarden Secrets Manager CLI."
  #exit 1
fi

# Function to ensure BW_SESSION is set and unlocked
ensure_session() {
  # If BW_SESSION is unset or expired, login/unlock
  if [[ -z "$BW_SESSION" ]] || ! bw status --session "$BW_SESSION" | grep -iq "unlocked"; then
    echo "=> Logging into Bitwarden using API key..."
    # Login with API key, output raw session
    export BW_SESSION=$(bw login --apikey --raw)
    if [[ -z "$BW_SESSION" ]]; then
      echo "Error: Failed to login to Bitwarden." >&2
      #exit 1
    fi
  fi
}

ensure_session

# Retrieve the secret data.
secret_data=$(bws secret get "$SECRET_ID" 2> /dev/null)

# Check if the secret retrieval was successful
if [ $? -ne 0 ]; then
  echo "Error: Failed to retrieve secret with ID '$SECRET_ID'."
  #exit 1
fi
#Check if secret_data is empty
if [ -z "$secret_data" ]; then
    echo "Error: retrieved empty secret"
    #exit 1
fi


BW_CLIENTID=$(echo "$secret_data" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="key"){print $(i+2)}}}')
BW_CLIENTSECRET=$(echo "$secret_data" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="value"){print $(i+2)}}}')

# Check if the variables were populated.
if [ -z "$BW_CLIENTID" ] || [ -z "$BW_CLIENTSECRET" ]; then
  echo "Error: Could not extract client_id or client_secret from the secret data.  Check the field names in your secret."
  #exit 1
fi
export BW_CLIENTID BW_CLIENTSECRET
export BW_SESSION=$(bw unlock --raw)

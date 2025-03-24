#!/bin/bash

# Secret ID
SECRET_ID="c368bb97-1837-46d1-ad26-b2aa0103cb25"

# Check if bws is installed.
if ! command -v bws &> /dev/null; then
  echo "Error: bws command not found.  Please install the Bitwarden Secrets Manager CLI."
  exit 1
fi

# Retrieve the secret data.
secret_data=$(bws secret get "$SECRET_ID" 2> /dev/null)

# Check if the secret retrieval was successful
if [ $? -ne 0 ]; then
  echo "Error: Failed to retrieve secret with ID '$SECRET_ID'."
  exit 1
fi
#Check if secret_data is empty
if [ -z "$secret_data" ]; then
    echo "Error: retrieved empty secret"
    exit 1
fi


BW_CLIENTID=$(echo "$secret_data" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="key"){print $(i+2)}}}')
BW_CLIENTSECRET=$(echo "$secret_data" | awk -F'"' '{for(i=1;i<=NF;i++){if($i=="value"){print $(i+2)}}}')

# Check if the variables were populated.
if [ -z "$BW_CLIENTID" ] || [ -z "$BW_CLIENTSECRET" ]; then
  echo "Error: Could not extract client_id or client_secret from the secret data.  Check the field names in your secret."
  exit 1
fi
export BW_CLIENTID BW_CLIENTSECRET

exit 0

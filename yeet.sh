#!/bin/bash

# --- Configuration ---
# AWKEYS_FOLDER_ID="${AWKEYS_FOLDER_ID:?Error: AWKEYS_FOLDER_ID is not set. Please set it to the Bitwarden folder ID.}" #Commented out now that we find folder.

# --- Functions ---

# Check if Bitwarden is logged in
bw_is_logged_in() {
  bw status | grep -q '"status":"unlocked"'
}

# List SSH keys in the AWKeys folder
list_keys() {
  if ! bw_is_logged_in; then
    echo "Error: Bitwarden is not logged in."
    exit 1
  fi

  # Get the folder ID using bw list folders and jq
  local folder_id=$(bw list folders --search AWKeys | jq -r '.[] | select(.name == "AWKeys") | .id')

  if [ -z "$folder_id" ]; then
    echo "Error: Could not find the AWKeys folder ID."
    exit 1
  fi

  # We no longer need the multiple ID check since we're selecting by name with jq.

  echo "Available SSH Keys in Bitwarden (AWKeys folder):"
  bw list items --folderid "$folder_id" | jq -r '.[] | select(.type == 1) | .name'
}

get_key() {
    if ! bw_is_logged_in; then
        echo "Error: Bitwarden is not logged in."
        exit 1
    fi
    local key_name="$1"
    if [ -z "$key_name" ]; then
        echo "Usage: $0 get <key_name>"
        exit 1
    fi

    # Get the folder ID (same logic as in list_keys)
    local folder_id=$(bw list folders --search AWKeys | jq -r '.[] | select(.name == "AWKeys") | .id')
    if [ -z "$folder_id" ]; then
      echo "Error: Could not find the AWKeys folder ID."
      exit 1
    fi
  # We no longer need the multiple ID check since we're selecting by name with jq.

    # Get the item ID by searching for the key name within the folder
    local item_id=$(bw list items --folderid "$folder_id" | jq -r --arg key_name "$key_name" '.[] | select(.type == 1 and .name == $key_name) | .id')

    if [ -z "$item_id" ]; then
        echo "Error: Could not find a key named '$key_name' in the AWKeys folder."
        exit 1
    fi

    # Retrieve the item and extract the private key
    local private_key=$(bw get item "$item_id" | jq -r '.notes')

    if [ -z "$private_key" ]; then
        echo "Error: Could not retrieve the private key from Bitwarden."
        exit 1
    fi

    # Save the private key to ~/.ssh/<key_name>
    local key_path="$HOME/.ssh/$key_name"
    echo "$private_key" > "$key_path"
    chmod 600 "$key_path"

    echo "Key '$key_name' retrieved and saved to '$key_path'"
}

create_key() {
  if ! bw_is_logged_in; then
    echo "Error: Bitwarden is not logged in."
    exit 1
  fi

  # Generate default key name: <hostname>-<YYYY-MM>
  local default_key_name=$(hostname -s)-$(date +%Y-%m)

  # Prompt for the key name, with a default value
  read -r -p "Enter a name for the new SSH key (default: $default_key_name): " key_name
  key_name="${key_name:-$default_key_name}" # Use default if input is empty

  if [ -z "$key_name" ]; then
    echo "Error: Key name cannot be empty."
    exit 1
  fi

  # Get the folder ID (same logic as in list_keys and get_key)
  local folder_id=$(bw list folders --search AWKeys | jq -r '.[] | select(.name == "AWKeys") | .id')
  if [ -z "$folder_id" ]; then
    echo "Error: Could not find the AWKeys folder ID."
    exit 1
  fi

  # Generate the SSH key pair
  local key_path="$HOME/.ssh/$key_name"
  if [ -f "$key_path" ]; then
      echo "Error: A key file already exists at '$key_path'."
      echo "       Please choose a different name or delete the existing file."
      exit 1
  fi
  ssh-keygen -t ed25519 -f "$key_path" -N ""  # -N "" for no passphrase

  if [ $? -ne 0 ]; then # Check exit status of ssh-keygen
      echo "Error: SSH key generation failed."
      exit 1
  fi

  # Read the private key content
  local private_key=$(cat "$key_path")

  # Create a new secure note in Bitwarden
  local bw_item=$(bw encode --input "$private_key" | jq -n --arg name "$key_name" --arg folderId "$folder_id" --arg notes "$(cat)" \
    '{type: 1, name: $name, notes: $notes, folderId: $folderId}')
  bw create item "$bw_item"
    if [ $? -ne 0 ]; then
      echo "Error: Failed to save the key to Bitwarden. The local key has been created."
      exit 1
    fi

  chmod 600 "$key_path"

  echo "SSH key '$key_name' created and saved to '$key_path' and Bitwarden."
}
# --- Main Script ---

# Check if Bitwarden CLI is installed
if ! command -v bw &> /dev/null; then
  echo "Error: Bitwarden CLI (bw) is not installed."
  exit 1
fi

#Default to showing help
if [ -z "$1" ]; then
   echo "Usage:"
   echo "  $0 list     - List available SSH keys"
   echo "  $0 get <keyname>   - Get a key"
   echo "Further actions will be available."
   exit 0
fi

case "$1" in
  list)
    list_keys
    ;;
  get)
    get_key "$2"
    ;;
  create)
    create_key
    ;;
  *)
    echo "Invalid command: $1"
    exit 1
    ;;
esac

exit 0

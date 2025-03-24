# List SSH keys in the AWKeys folder
list_keys() {
  if ! bw_is_logged_in; then
    echo "Error: Bitwarden is not logged in."
    exit 1
  fi

  # Get the folder ID using bw list folders and awk
  local folder_id=$(bw list folders --search AWKeys | awk -F'\t' '$2 ~ /AWKeys/ {print $1}')

  if [ -z "$folder_id" ]; then
    echo "Error: Could not find the AWKeys folder ID."
    exit 1
  fi
  # Check for multiple matches, just in case. This is a safety net.
  if [ $(echo "$folder_id" | wc -l) -gt 1 ]; then
      echo "Error: Multiple folders found matching 'AWKeys'.  Please ensure the folder name is unique."
      echo "Found IDs:"
      echo "$folder_id"
      exit 1
  fi

  echo "Available SSH Keys in Bitwarden (AWKeys folder):"
  bw list items --folderid "$folder_id" | jq -r '.[] | select(.type == 1) | .name'
}
# ... (bw_is_logged_in and list_keys remain the same) ...
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
    local folder_id=$(bw list folders --search AWKeys | awk -F'\t' '$2 ~ /AWKeys/ {print $1}')
    if [ -z "$folder_id" ]; then
      echo "Error: Could not find the AWKeys folder ID."
      exit 1
    fi
    if [ $(echo "$folder_id" | wc -l) -gt 1 ]; then
        echo "Error: Multiple folders found matching 'AWKeys'."
        exit 1
    fi

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
# --- Main Script ---
# ... (Help and 'list' case remain the same) ...
  get)
    get_key "$2"
    ;;
# ... (rest of the script) ...

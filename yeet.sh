#!/bin/bash

bw_is_logged_in() {
  bw status | grep -q '"status":"unlocked"'
}

list_keys() {
  if ! bw_is_logged_in; then
    echo "Error: Bitwarden is not logged in."
    exit 1
  fi

  echo "Available SSH Keys in Bitwarden:"
  bw list items | jq -r '.[] | select(.type == 5) | .name'
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
    local item_id=$(bw list items | jq -r --arg key_name "$key_name" '.[] | select(.type == 5 and .name == $key_name) | .id')

    if [ -z "$item_id" ]; then
        echo "Error: Could not find a key named '$key_name'."
        exit 1
    fi

    local item_json=$(bw get item "$item_id")

    local private_key=$(echo "$item_json" | jq -r '.sshKey.privateKey')
    local public_key=$(echo "$item_json" | jq -r '.sshKey.publicKey')

    if [ -z "$private_key" ] || [ -z "$public_key" ]; then
        echo "Error: Could not retrieve the private or public key from Bitwarden."
        exit 1
    fi

    local key_path="$HOME/.ssh/$key_name"
    echo "$private_key" > "$key_path"
    chmod 600 "$key_path"
    echo "Private key '$key_name' saved to '$key_path'"
    read -r -p "Add public key to ~/.ssh/authorized_keys? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "$public_key" >> "$HOME/.ssh/authorized_keys"
        chmod 600 "$HOME/.ssh/authorized_keys"
        echo "Public key added to ~/.ssh/authorized_keys"
    else
        echo "Public key not added to ~/.ssh/authorized_keys"
    fi
}

create_key() {
  if ! bw_is_logged_in; then
    echo "Error: Bitwarden is not logged in."
    exit 1
  fi

  local default_key_name=$(hostname -s)-$(date +%Y-%m)
  read -r -p "Enter a name for the new SSH key (default: $default_key_name): " key_name
  key_name="${key_name:-$default_key_name}"

  if [ -z "$key_name" ]; then
    echo "Error: Key name cannot be empty."
    exit 1
  fi

  local key_path="$HOME/.ssh/$key_name"
  if [ -f "$key_path" ]; then
      echo "Error: A key file already exists at '$key_path'."
      exit 1
  fi
  ssh-keygen -t ed25519 -f "$key_path" -N ""

  if [ $? -ne 0 ]; then
    echo "Error: SSH key generation failed."
    exit 1
  fi

  local private_key=$(cat "$key_path") 
  local public_key=$(cat "$key_path.pub")

  local key_fingerprint=$(ssh-keygen -lf "$key_path" | awk '{print $2}')

  bw get template item | \
    jq --arg name "$key_name" --arg privateKey "$private_key" --arg publicKey "$public_key" --arg keyFingerprint "$key_fingerprint" '. + {type: 5, name: $name, sshKey: {privateKey: $privateKey, publicKey: $publicKey, keyFingerprint: $keyFingerprint}}' | \
    bw encode | \
    bw create item > /dev/null 2>&1

  if [ $? -ne 0 ]; then
    echo "Error: Failed to save the key to Bitwarden. The local key has been created."
    exit 1
  fi

  chmod 600 "$key_path"
  echo "SSH key '$key_name' created and saved to '$key_path' and Bitwarden."

  read -r -p "Add public key to ~/.ssh/authorized_keys? (y/n): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
      echo "$public_key" >> "$HOME/.ssh/authorized_keys"
      chmod 600 "$HOME/.ssh/authorized_keys"
      echo "Public key added to ~/.ssh/authorized_keys"
  else
      echo "Public key not added to ~/.ssh/authorized_keys"
  fi
}

if ! command -v bw &> /dev/null; then
  echo "Error: Bitwarden CLI (bw) is not installed."
  exit 1
fi

if [ -z "$1" ]; then
    echo "Usage:"
    echo "  $0 list      - List available SSH keys"
    echo "  $0 get <keyname> - Get a key and add pub key to authorized_keys"
    echo "  $0 create    - Creates and upload a key"
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

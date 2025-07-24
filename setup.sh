#!/usr/bin/env bash
set -euo pipefail

# Function to install a prerequisite package if it's not already installed
install_prerequisite() {
  local pkg="$1"
  if ! command -v "$pkg" >/dev/null 2>&1; then
    echo "Installing $pkg..."
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y "$pkg"
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y "$pkg"
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "$pkg"
    else
      echo "Error: Could not find a package manager (apt-get, yum, dnf). Please install $pkg manually." >&2
      exit 1
    fi
  fi
}

# Function to install a tool from a URL
install_from_url() {
  local tool_name=$1
  local download_url=$2
  local install_dir=$3
  local version=$4
  local file_name=$5
  local is_zip=$6

  if command -v "$tool_name" >/dev/null 2>&1; then
    echo "$tool_name is already installed."
    return
  fi

  mkdir -p "$install_dir"
  echo "Downloading $tool_name ${version}..."
  curl -L "$download_url" -o "/tmp/$file_name"

  if [[ "$is_zip" = true ]]; then
    unzip -o "/tmp/$file_name" -d "/tmp/${tool_name}-temp"
    mv "/tmp/${tool_name}-temp/$tool_name" "$install_dir/"
    rm -rf "/tmp/$file_name" "/tmp/${tool_name}-temp"
  else
    mv "/tmp/$file_name" "$install_dir/$tool_name"
  fi

  chmod +x "$install_dir/$tool_name"
  echo "$tool_name has been installed to $install_dir/$tool_name"
}

# Function to ensure a directory is in the PATH
ensure_path() {
  local target_dir=$1
  if [[ ":$PATH:" != *":${target_dir}:"* ]]; then
    echo "Adding ${target_dir} to PATH in ~/.bashrc"
    echo "export PATH=\"\$PATH:${target_dir}\"" >> "${HOME}/.bashrc"
    echo "Please run 'source ~/.bashrc' or start a new terminal session to update your PATH."
  fi
}

main() {
  # Install prerequisites
  install_prerequisite curl
  install_prerequisite unzip
  install_prerequisite git

  # Configuration for tools
  local install_dir="${HOME}/.local/bin"
  local jq_version="1.7"
  local jq_filename="jq-linux-amd64"
  local bw_version="2025.2.0"
  local bws_version="1.0.0"
  local bws_arch="x86_64-unknown-linux-gnu"

  # Install tools
  install_from_url "jq" "https://github.com/jqlang/jq/releases/download/jq-${jq_version}/${jq_filename}" "$install_dir" "$jq_version" "$jq_filename" false
  install_from_url "bw" "https://github.com/bitwarden/clients/releases/download/cli-v${bw_version}/bw-linux-${bw_version}.zip" "$install_dir" "$bw_version" "bw.zip" true
  install_from_url "bws" "https://github.com/bitwarden/sdk-sm/releases/download/bws-v${bws_version}/bws-${bws_arch}-${bws_version}.zip" "$install_dir" "$bws_version" "bws.zip" true

  # Ensure the install directory is in the PATH
  ensure_path "$install_dir"

  echo "Setup complete."
}

main "$@"

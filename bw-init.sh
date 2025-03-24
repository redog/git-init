#!/bin/bash

# Define variables
BW_VERSION="2025.2.0"
DOWNLOAD_URL="https://github.com/bitwarden/clients/releases/download/cli-v${BW_VERSION}/bw-linux-${BW_VERSION}.zip"
INSTALL_DIR="/usr/local/bin"

# Print start message
echo "Starting Bitwarden CLI installation..."

# Check if wget is installed
if ! command -v wget &> /dev/null; then
    echo "wget is not installed. Installing wget..."
    sudo apt-get update && sudo apt-get install wget -y
fi

# Check if unzip is installed
if ! command -v unzip &> /dev/null; then
    echo "unzip is not installed. Installing unzip..."
    sudo apt-get update && sudo apt-get install unzip -y
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Download the Bitwarden CLI
echo "Downloading Bitwarden CLI..."
wget "$DOWNLOAD_URL" -O bw.zip

# Unzip the package
echo "Extracting files..."
unzip bw.zip

# Make the binary executable
chmod +x bw

# Move the binary to the installation directory
echo "Installing Bitwarden CLI to $INSTALL_DIR..."
sudo mv bw "$INSTALL_DIR"

# Clean up
cd - > /dev/null
rm -rf "$TEMP_DIR"

# Verify installation
if command -v bw &> /dev/null; then
    echo "Bitwarden CLI has been successfully installed!"
    echo "Version installed: $(bw --version)"
else
    echo "Installation failed!"
    exit 1
fi

echo "You can now use the 'bw' command to access Bitwarden CLI."

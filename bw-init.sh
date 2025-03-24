#!/bin/bash

set -euo pipefail

# Configuration
VERSION="2025.2.0"
FILENAME="bw-linux-${VERSION}.zip"
DOWNLOAD_URL="https://github.com/bitwarden/clients/releases/download/cli-v${VERSION}/${FILENAME}"
INSTALL_DIR="${HOME}/.local/bin"
CHECKSUM_URL="https://github.com/bitwarden/clients/releases/download/cli-v${VERSION}/bw-linux-sha256-${VERSION}.txt"

# Create installation directory if it doesn't exist
mkdir -p "${INSTALL_DIR}"

# Download the zip file and checksum
echo "Downloading Bitwarden CLI..."
curl -L -o "/tmp/${FILENAME}" "${DOWNLOAD_URL}"
curl -L -o "/tmp/checksum.txt" "${CHECKSUM_URL}"

# Verify checksum
echo "Verifying download..."
cd /tmp
if ! sha256sum -c checksum.txt; then
    echo "Checksum verification failed!"
    rm -f "/tmp/${FILENAME}" "/tmp/checksum.txt"
    exit 1
fi

# Unzip to temporary location
echo "Extracting..."
unzip -o "/tmp/${FILENAME}" -d "/tmp/bw-temp"

# Move binary to installation directory
echo "Installing..."
mv "/tmp/bw-temp/bw" "${INSTALL_DIR}/bw"
chmod +x "${INSTALL_DIR}/bw"

# Clean up
rm -rf "/tmp/${FILENAME}" "/tmp/bw-temp" "/tmp/checksum.txt"

# Check if INSTALL_DIR is in PATH
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo "Adding ${INSTALL_DIR} to PATH in ~/.bashrc"
    echo "export PATH=\"\$PATH:${INSTALL_DIR}\"" >> "${HOME}/.bashrc"
    echo "Please run 'source ~/.bashrc' or start a new terminal session"
fi

# Setup shell completions
if [ -d "${HOME}/.local/share/bash-completion/completions" ]; then
    echo "Setting up bash completion..."
    bw completion --shell bash > "${HOME}/.local/share/bash-completion/completions/bw"
fi

if [ -d "${HOME}/.local/share/zsh/site-functions" ]; then
    echo "Setting up zsh completion..."
    mkdir -p "${HOME}/.local/share/zsh/site-functions"
    bw completion --shell zsh > "${HOME}/.local/share/zsh/site-functions/_bw"
fi

echo "Installation complete! bw has been installed to ${INSTALL_DIR}/bw"
echo "Verify installation with: bw --version"
echo ""
echo "To get started:"
echo "1. Run 'bw login' to log in to your Bitwarden account"
echo "2. Run 'bw unlock' to unlock your vault"
echo "3. Run 'bw --help' to see available commands"

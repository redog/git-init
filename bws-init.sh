#!/bin/bash

set -euo pipefail

# Configuration
VERSION="1.0.0"
ARCH="x86_64-unknown-linux-gnu"
FILENAME="bws-${ARCH}-${VERSION}.zip"
DOWNLOAD_URL="https://github.com/bitwarden/sdk-sm/releases/download/bws-v${VERSION}/${FILENAME}"
INSTALL_DIR="${HOME}/.local/bin"

# Create installation directory if it doesn't exist
mkdir -p "${INSTALL_DIR}"

# Download the zip file
echo "Downloading bws..."
curl -L -o "/tmp/${FILENAME}" "${DOWNLOAD_URL}"

# Unzip to temporary location
echo "Extracting..."
unzip -o "/tmp/${FILENAME}" -d "/tmp/bws-temp"

# Move binary to installation directory
echo "Installing..."
mv "/tmp/bws-temp/bws" "${INSTALL_DIR}/bws"
chmod +x "${INSTALL_DIR}/bws"

# Clean up
rm -rf "/tmp/${FILENAME}" "/tmp/bws-temp"

# Check if INSTALL_DIR is in PATH
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo "Add ${INSTALL_DIR} to PATH in ~/.bashrc"
    echo "export PATH=\"\$PATH:${INSTALL_DIR}\"" >> "${HOME}/.bashrc"
    echo "Please run 'source ~/.bashrc' or start a new terminal session"
fi

echo "Installation complete! bws has been installed to ${INSTALL_DIR}/bws"
echo "Verify installation with: bws --version"

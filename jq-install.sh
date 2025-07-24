#!/bin/bash

set -euo pipefail

# Configuration
JQ_VERSION="1.7"
JQ_FILENAME="jq-linux-amd64"
DOWNLOAD_URL="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/${JQ_FILENAME}"
INSTALL_DIR="${HOME}/.local/bin"

mkdir -p "${INSTALL_DIR}"

# Download the jq binary
echo "Downloading jq ${JQ_VERSION}..."
curl -L -o "${INSTALL_DIR}/jq" "${DOWNLOAD_URL}"

# Make it executable
chmod +x "${INSTALL_DIR}/jq"

# Add INSTALL_DIR to PATH if necessary
if [[ ":$PATH:" != *":${INSTALL_DIR}:"* ]]; then
    echo "Adding ${INSTALL_DIR} to PATH in ~/.bashrc"
    echo "export PATH=\"\$PATH:${INSTALL_DIR}\"" >> "${HOME}/.bashrc"
    echo "Please run 'source ~/.bashrc' or start a new terminal session"
fi

echo "jq has been installed to ${INSTALL_DIR}/jq"
echo "Verify installation with: jq --version"

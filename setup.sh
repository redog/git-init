#!/usr/bin/env bash
set -euo pipefail

install_prerequisite() {
  local pkg="$1"
  if ! command -v "$pkg" >/dev/null 2>&1; then
    echo "Installing $pkg..."
    sudo apt-get update && sudo apt-get install -y "$pkg"
  fi
}

install_jq() {
  if command -v jq >/dev/null 2>&1; then
    echo "jq is already installed."
  else
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
  fi
}

install_bw() {
  if command -v bw >/dev/null 2>&1; then
    echo "bw is already installed."
    return
  fi
  local BW_VERSION="2025.2.0"
  local DOWNLOAD_URL="https://github.com/bitwarden/clients/releases/download/cli-v${BW_VERSION}/bw-linux-${BW_VERSION}.zip"
  local INSTALL_DIR="${HOME}/.local/bin"
  mkdir -p "$INSTALL_DIR"
  echo "Downloading bw ${BW_VERSION}..."
  curl -L "$DOWNLOAD_URL" -o /tmp/bw.zip
  unzip -o /tmp/bw.zip -d /tmp/bw-temp
  mv /tmp/bw-temp/bw "$INSTALL_DIR/"
  chmod +x "$INSTALL_DIR/bw"
  rm -rf /tmp/bw.zip /tmp/bw-temp
  echo "bw installed to $INSTALL_DIR/bw"
}

install_bws() {
  if command -v bws >/dev/null 2>&1; then
    echo "bws is already installed."
    return
  fi
  local VERSION="1.0.0"
  local ARCH="x86_64-unknown-linux-gnu"
  local FILENAME="bws-${ARCH}-${VERSION}.zip"
  local DOWNLOAD_URL="https://github.com/bitwarden/sdk-sm/releases/download/bws-v${VERSION}/${FILENAME}"
  local INSTALL_DIR="${HOME}/.local/bin"
  mkdir -p "$INSTALL_DIR"
  echo "Downloading bws ${VERSION}..."
  curl -L -o "/tmp/${FILENAME}" "$DOWNLOAD_URL"
  unzip -o "/tmp/${FILENAME}" -d /tmp/bws-temp
  mv /tmp/bws-temp/bws "$INSTALL_DIR/"
  chmod +x "$INSTALL_DIR/bws"
  rm -rf "/tmp/${FILENAME}" /tmp/bws-temp
  echo "bws installed to $INSTALL_DIR/bws"
}

ensure_path() {
  local target="${HOME}/.local/bin"
  if [[ ":$PATH:" != *":${target}:"* ]]; then
    echo "Adding ${target} to PATH in ~/.bashrc"
    echo "export PATH=\"\$PATH:${target}\"" >> "${HOME}/.bashrc"
  fi
}

main() {
  install_prerequisite curl
  install_prerequisite unzip
  install_prerequisite git

  install_jq
  install_bw
  install_bws

  ensure_path

  echo "Setup complete."
}

main "$@"

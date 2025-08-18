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
  local arch="$1"
  if command -v jq >/dev/null 2>&1; then
    echo "jq is already installed."
  else
	# Configuration
	JQ_VERSION="1.8.1"
	JQ_FILENAME="jq-linux-${arch}"
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
  local arch="$1"
  if command -v bw >/dev/null 2>&1; then
    echo "bw is already installed."
    return
  fi
  local BW_VERSION="2025.7.0"
  local zip_suffix=""
  if [[ "$arch" == "arm64" ]]; then
    zip_suffix="-${arch}"
  fi
  local DOWNLOAD_URL="https://github.com/bitwarden/clients/releases/download/cli-v${BW_VERSION}/bw-linux${zip_suffix}-${BW_VERSION}.zip"
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
  local arch="$1"
  if command -v bws >/dev/null 2>&1; then
    echo "bws is already installed."
    return
  fi
  local VERSION="1.0.0"
  local bws_arch
  if [[ "$arch" == "amd64" ]]; then
    bws_arch="x86_64-unknown-linux-gnu"
  else
    bws_arch="aarch64-unknown-linux-gnu"
  fi
  local FILENAME="bws-${bws_arch}-${VERSION}.zip"
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
  # Detect architecture
  local arch
  case "$(uname -m)" in
    "x86_64")
      arch="amd64"
      ;;
    "aarch64")
      arch="arm64"
      ;;
    *)
      echo "Unsupported architecture: $(uname -m)"
      exit 1
      ;;
  esac

  install_prerequisite curl
  install_prerequisite unzip
  install_prerequisite git

  install_jq "$arch"
  install_bw "$arch"
  install_bws "$arch"

  ensure_path

  echo "Setup complete."
}

main "$@"

#!/bin/bash

# Short and simple jq installer for apt-based systems (Debian/Ubuntu).

if command -v jq &> /dev/null; then
  echo "jq is already installed."
  exit 0
fi

echo "Installing jq..."
sudo apt-get update && sudo apt-get install -y jq

if command -v jq &> /dev/null; then
  echo "jq installed successfully."
else
  echo "jq installation failed."
  exit 1
fi

#!/bin/bash

# Short and simple git installer for apt-based systems (Debian/Ubuntu).

if command -v git &> /dev/null; then
  echo "git is already installed."
  exit 0
fi

echo "Installing git..."
sudo apt-get update && sudo apt-get install -y git

if command -v git &> /dev/null; then
  echo "git installed successfully."
else
  echo "git installation failed."
  exit 1
fi

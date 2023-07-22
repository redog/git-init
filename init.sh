#!/bin/bash

MYINIT="git-init"

# Attempt to retrieve the password
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  pass=$(security find-generic-password -s 'github' -w 2>/dev/null)
  if [[ $? -ne 0 ]]; then
    echo "Failed to retrieve GitHub password"
    exit 1
  fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  # Linux
  # Replace this with the actual command for Linux
  echo "Linux not yet supported"
  exit 1
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  # Windows
  # Replace this with the actual command for Windows
  echo "Windows not yet supported"
  exit 1
else
  # Unknown OS
  echo "Unsupported OS"
  exit 1
fi

export GITHUB_ACCESS_TOKEN="$pass"
python3 ${MYINIT}/mkrepo.py
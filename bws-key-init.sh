#!/bin/env bash

# Load bitwarden secrets key
load_bws_key() {
  local pass verbose=false proj

  # Check for verbose flag
  if [[ $1 == "-v" ]]; then
    verbose=true
    shift
  fi

  # Check if the access token is already set and non-empty
  if [[ -n "$BWS_ACCESS_TOKEN" ]]; then
    $verbose && echo "Bitwarden access token already set."
    pass="$BWS_ACCESS_TOKEN"
  else
    # Detect shell and load password accordingly
    case "$SHELL" in
      *zsh*)
        pass=$(security find-generic-password -s 'bitwarden' -w 2>/dev/null)
        ;;
      *bash*)
        export DISPLAY=:0
        pass=$(secret-tool lookup bitwarden accesstoken 2>/dev/null)
        ;;
      *)
        echo "Unsupported shell: $SHELL"
        return 1
        ;;
    esac

    if [[ -z "$pass" ]]; then
      echo "Failed to retrieve Bitwarden key."
      return 1
    fi

    export BWS_ACCESS_TOKEN="$pass"
    $verbose && echo "Loading Bitwarden key..."
  fi

  # Get the project ID (regardless of whether token was already set)
  if ! proj=$(bws project list -o tsv 2>/dev/null | tail -n 1 | awk '{print $1}'); then
    echo "Failed to list projects."
    return 1
  fi

  if [[ -z "$proj" ]]; then
    echo "No project or id found."
    return 1
  fi

  export BWS_PROJECT_ID="$proj"
  $verbose && echo "Project ID set to $proj."
  return 0
}

load_bws_key

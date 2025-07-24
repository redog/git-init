git-init
========

# Prerequisites
  1. Curl - unzip - python3 - python-venv - jq - wget
  
  1. bws - bitwarden sdk (secrets manager) & bw - bitwarden cli
    
     ```
     bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/bws-install.sh)
     bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/bw-install.sh)
  1. requests python module
    
     ```
     python -m venv venv
     source venv/bin/activate
     pip install requests
  1. git credential manager

    
     ```  
     read BWS_ACCESS_TOKEN
     export BWS_ACCESS_TOKEN
     echo -n "$BWS_ACCESS_TOKEN" | secret-tool store --label="Bitwarden Access Token" bitwarden accesstoken


# Get it and init it

bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)

or

# Source the key initialization script so that environment variables such as
# `BW_SESSION` are exported to your current shell.
source ./bw-key-init.sh
./bws-key-init.sh
./init.sh

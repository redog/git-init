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

# Get it and init it

bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)

or

./init.sh

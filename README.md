git-init
========

# Prerequsites
  1. Curl - unzip - python3 - python-venv - jq - wget
  
  1. bws - bitwarden sdk (secrets manager) & bw - bitwarden cli
    
     ```
     bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/bws-install.sh)
     bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/bw-install.sh)
  1. requests python module

    
     ```
     python -m venv venv
     ./venv/bin/activate
     source venv/bin/activate
     pip install requests
  1. git credential manager

    
     ```  
     read BITWARDEN_ACCESS_TOKEN
     export BITWARDEN_ACCESS_TOKEN

# Get it and init it

bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)

or

./src/git-init/init.sh

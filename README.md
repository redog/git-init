git-init
========

# Prerequsites:
  1.) bws - bitwarden sdk (secrets manager) & bw - bitwarden cli

    * bws-init.sh

    * bw-init.sh
    
  2.) requests python module

  3.) git credential manager

python -m venv venv

./venv/bin/activate

source venv/bin/activate

pip install requests
  
read BITWARDEN_ACCESS_TOKEN

export BITWARDEN_ACCESS_TOKEN

# Get it and init it
#bash <(wget -q) - https://raw.githubusercontent.com/redog/git-init/master/init.sh

bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)

or

./src/git-init/init.sh

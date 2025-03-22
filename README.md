git-init
========

# Prerequsites:
  1.) bws - bitwarden sdk (secrets manager)
  2.) requests python module

python -m venv venv

./venv/bin/activate

source venv/bin/activate

pip install requests
  
# Get it and init it
#bash <(wget -q) - https://raw.githubusercontent.com/redog/git-init/master/init.sh

bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)

or

./src/git-init/init.sh

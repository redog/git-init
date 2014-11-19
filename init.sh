#!/bin/bash

#sudo wget this?
mkdir ~/tmp
MYINIT="git-init"
sudo apt-get install git
sudo git clone https://github.com/redog/git-init

python ${MYINIT}/configure.py
#sudo ${MYINIT}/authtoken.py

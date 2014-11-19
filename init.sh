#!/bin/bash

#sudo wget this?
mkdir ~/tmp
MYINIT="git-init"
sudo apt-get install git
sudo git clone https://github.com/redog/git-init

sudo ${MYINIT}/configure.sh
#sudo ${MYINIT}/authtoken.py

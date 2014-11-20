#!/bin/bash

#sudo wget this?
mkdir ~/tmp
MYINIT="git-init"
sudo apt-get install git
git clone https://github.com/redog/git-init

# configure git 
#python ${MYINIT}/configure.py

# configure git & github
python ${MYINIT}/authtoken.py


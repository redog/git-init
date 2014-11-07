#!/bin/bash

#sudo wget this?
mkdir ~/tmp
sudo apt-get install git
sudo git clone https://github.com/redog/git-init
sudo git-init/configure.sh
sudo git-init/authtoken.py 
#sudo git-init/ghcreaterepo.py

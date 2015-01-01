#!/bin/sh -

#sudo wget this?
mkdir ~/tmp
MYINIT="git-init"
<<<<<<< HEAD
sudo apt-get install -y git
sudo git clone https://github.com/redog/git-init
=======
sudo apt-get install git
git clone https://github.com/redog/git-init
>>>>>>> 97b1b4a54a7435f91922e172ff336e35da622bb9

sudo apt-get install -y vcsh
vcsh -f clone  https://github.com/redog/rc.git vim
vcsh vim reset --hard origin/master
sudo apt-get intall -y awscli
sudo apt-get intall -y fabric
sudo apt-get intall -y vim
sudo apt-get intall -y boto


# configure git 
#python ${MYINIT}/configure.py

# configure git & github
python ${MYINIT}/authtoken.py


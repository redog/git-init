#!/bin/bash
#TODO sysargv validation & switches
	git config --global user.name "${1}"
	git config --global user.email "${2}"
	git config --global user.github.login.name "${3}"
	git config --global user.github.token "${4}"
	git config --global credential.helper 'cache --timeout=1800'
	git config --global push.default simple

# add the following to ~/.netrc
#machine github.com
#login redog
#password <token>



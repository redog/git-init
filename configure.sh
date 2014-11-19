#!/bin/bash
#TODO sysargv validation & switches
	git config --global user.name $1
	git config --global user.email $2
	git config --global user.github.login.name $3
	git config --global credential helper 'cache --timeout=300'
	git confgig --global push.default simple

GITHUB_API = 'https://api.github.com'

import requests
import getpass
import json
# python 3
from urllib.parse import urljoin
# python 2?
#from urlparse import urljoin
import sys, os
import subprocess
from ast import literal_eval

FNULL = open(os.devnull, 'w')

def safeinput(s):
    try:
        return literal_eval(s)
    except:
        return s
#python2?
#old_raw_input = raw_input
#python2?
#def raw_input(*args):
#    old_stdout = sys.stdout
#    try:
#        sys.stdout=sys.stderr
#        return old_raw_input(*args)
#    finally:
#        sys.stdout=old_stdout

def main():
    #
    # User Input
    #
    home = os.environ['HOME']
    curd = os.getcwd()
    name = input('Full Name: ')
    email = input('Email Address: ')
    username = input('Github username: ')
    k
    password = getpass.getpass('Github password: ')
	#No longer optional ?
    #note = safeinput(input('Note (optional): '))
    note = safeinput(input('Note: '))
    #
    # Compose Request
    #
    url = urljoin(GITHUB_API, 'authorizations')
    payload = {}
    if note:
        payload['note'] = note
    payload['scopes'] = ["repo"]
    res = requests.post(
        url,
        auth = (username, password),
        data = json.dumps(payload),
        )
    #
    # Parse Response
    #
    j = json.loads(res.text)
    token = j['token']
    print(token)
   #
   # Configure git & github
   #
   # print(['/bin/bash', home+'/git-init/configure.sh', name, email, username, token ])
   # cmd = ['/bin/bash', home+'/git-init/configure.sh', name, email, username, token ]
    print(['/bin/bash', curd+'/configure.sh', name, email, username, token ])
    cmd = ['/bin/bash', curd+'/configure.sh', name, email, username, token ]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
    rslt, error = p.communicate()
###
#    print(token)

if __name__ == '__main__':
    main()


GITHUB_API = 'https://api.github.com'


import requests
import getpass
import json
from urlparse import urljoin
import sys
from ast import literal_eval
import subprocess
import os

FNULL = open(os.devnull, 'w')

p = subprocess.Popen(['/usr/bin/git', 'config', '--global', 'user.github.token'], stdout=subprocess.PIPE)
username, error = p.communicate()


def safeinput(s):
    try:
        return literal_eval(s)
    except:
        return s


def main(argv):
    if len(argv) is 1:
        note = safeinput(raw_input('Enter a unique name for the new repo: '))
    else:
        note = safeinput(sys.argv[1])

    #
    # Compose Request
    #
    url = urljoin(GITHUB_API, '/user/repos')
    payload = {}
    headers = {}
    headers['Content-Type'] = 'application/json'
#    headers['X-OAuth-Scopes'] = 'public_repo'
    headers['Authorization'] = 'token %s' % username.strip()


    payload['name'] = note
    payload['auto_init'] = True
    payload['private'] = False

    jhead = headers
    #jhead = json.dumps(headers)
    jpayld = json.dumps(payload)

    print(jhead)

    res2 = requests.post(url, headers=jhead, data=jpayld)
    print(res2.status_code)

    j2 = json.loads(res2.text)
    print(j2)

if __name__ == '__main__':
    main(sys.argv)

GITHUB_API = 'https://api.github.com'

import requests
import getpass
import json
from urlparse import urljoin
import sys
from ast import literal_eval

def safeinput(s):
    try:
        return literal_eval(s)
    except:
        return s

old_raw_input = raw_input

def raw_input(*args):
    old_stdout = sys.stdout
    try:
        sys.stdout=sys.stderr
        return old_raw_input(*args)
    finally:
        sys.stdout=old_stdout

def main(argv):
    #
    # User Input
    #
    username = raw_input('Github username: ')
    password = getpass.getpass('Github password: ')
    if len(argv) is 0:
        note = safeinput(raw_input('Note (optional): '))
    else:
        note = safeinput(sys.argv[1])

    #
    # Compose Request
    #
    url = urljoin(GITHUB_API, 'authorizations')
    payload = {}
    if note:
        payload['note'] = note
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

if __name__ == '__main__':
    main(sys.argv)

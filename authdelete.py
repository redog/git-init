GITHUB_API = 'https://api.github.com'


import requests
import getpass
import json
from urlparse import urljoin
from ast import literal_eval
import sys


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

def main():
    #
    # User Input
    #
    username = raw_input('Github username: ')
    password = getpass.getpass('Github password: ')
    #
    # Compose Request
    #
    url = urljoin(GITHUB_API, 'authorizations')
    payload = {}
    res = requests.get(
        url,
        auth = (username, password),
        data = json.dumps(payload),
        )
    #
    # Parse Response
    #
    j = json.loads(res.text)
    i = 0
    dlst = {}
    for app in j:
         dlst[i] = app['id']
         print("[" +  str(i) + "]"),
         print(app['id']),
         print(app['app']['name'])
         i+=1

    todel = safeinput(raw_input('Select the token to delete: '))
    print type(todel)
    if type(todel) is int:
        #
        # Compose Request
        #
        url = urljoin(GITHUB_API, 'authorizations/' + str(dlst[todel]))
        print(url)
        payload = {}
        res = requests.delete(
            url,
            auth = (username, password),
            data = json.dumps(payload),
            )

if __name__ == '__main__':
    main()

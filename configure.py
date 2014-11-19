import getpass
import sys, os
import subprocess
from ast import literal_eval

FNULL= open(os.devnull, 'w')

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
    #TODO: validate?
    username = raw_input('Git username: ')
    email = raw_input('Git email: ')
    githubuser = raw_input('Github login name: ')
    p = subprocess.Popen(['bash -c ./configure.sh', username, email, githubuser], stdout=subprocess.PIPE)
    rslt, error = p.communicate()


if __name__ == '__main__':
    main()


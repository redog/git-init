import requests
import json
import os
import subprocess
import re

# Define a simple email validation function
def validate_email(email):
    if re.match(r"[^@]+@[^@]+\.[^@]+", email):
        return True
    else:
        print("Invalid email address. Please try again.")
        return False

home = os.environ['HOME']

# Input and validation loop for Full Name
while True:
    name = input('Full Name: ')
    if name:
        break
    else:
        print("Full name cannot be empty. Please try again.")

# Input and validation loop for Email Address
while True:
    email = input('Email Address: ')
    if validate_email(email):
        break

# Input and validation loop for Github username
while True:
    username = input('Github username: ')
    if username:
        break
    else:
        print("Github username cannot be empty. Please try again.")

# Input and validation loop for repo name
while True:
    repo = input('Enter a unique name for the new repo: ')
    if repo:
        break
    else:
        print("Repo name cannot be empty. Please try again.")

# Retrieve GitHub token from environment variable
try:
    token = os.environ["GITHUB_ACCESS_TOKEN"]
except KeyError:
    print("The GITHUB_ACCESS_TOKEN environment variable is not set.")
    exit(1)

api_url = f"https://api.github.com/user/repos"
headers = {'Authorization': f'token {token}', 'Accept': 'application/vnd.github.v3+json'}

data = {
    'name': repo,
    'description': 'Created with the GitHub API',
    'private': True,
}
try:
    response = requests.post(api_url, headers=headers, data=json.dumps(data))
    response.raise_for_status()  # Raise an exception for HTTP errors
except requests.exceptions.RequestException as e:
    print(f"Failed to create repository: {e}")
    exit(1)

if response.status_code == 201:
    print(f'Successfully created repository "{data["name"]}"')
else:
    print('Failed to create repository')

os.chdir(./git-init/)
cwd = os.getcwd()
cmd = ['/bin/bash', cwd+'/configure.sh', name, email, username, token, repo]
try:
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = p.communicate()
    if p.returncode != 0:
        print(f"Failed to execute command: {cmd}")
        print(stderr.decode())
        exit(1)
except Exception as e:
    print(f"Failed to execute command: {e}")
    exit(1)

import requests
import json
import os
import subprocess
import re

script_dir = os.path.dirname(os.path.abspath(__file__))
config_script = os.path.join(script_dir, 'configure.sh')

# Define a simple email validation function
def validate_email(email):
    if re.match(r"[^@]+@[^@]+\.[^@]+", email):
        return True
    else:
        print("Invalid email address. Please try again.")
        return False

def get_git_config():
    result = subprocess.run(['git', 'config', '--global', '-l'], stdout=subprocess.PIPE)
    config = {}
    if result.returncode == 0:
        lines = result.stdout.decode().strip().split('\n')
        for line in lines:
            key, value = line.split('=', 1)
            config[key] = value
    return config

# Get Git configuration
git_config = get_git_config()

home = os.environ['HOME']

# Retrieve or prompt for Full Name
name = git_config.get('user.name')
if not name:
    while True:
        name = input('Full Name: ')
        if name:
            break
        else:
            print("Full name cannot be empty. Please try again.")

# Retrieve or prompt for Email Address
email = git_config.get('user.email')
if not email:
    while True:
        email = input('Email Address: ')
        if validate_email(email):
            break

# Prompt for GitHub username
username = git_config.get('user.github.login.name')
if not username:
    while True:
        username = input('GitHub username: ')
        if username:
            break
        else:
            print("GitHub username cannot be empty. Please try again.")

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

cmd = ['/bin/bash', config_script, name, email, username, token, repo]

try:
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=script_dir)
    stdout, stderr = p.communicate()
    if p.returncode != 0:
        print(f"Failed to execute command: {cmd}")
        print(stderr.decode())
        exit(1)
except Exception as e:
    print(f"Failed to execute command: {e}")
    exit(1)

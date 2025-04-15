# -*- coding: utf-8 -*-
"""
This script automates GitHub repository management tasks:
- Fetches a GitHub Personal Access Token securely using Bitwarden CLI (bws).
- Allows cloning existing repositories owned by the user.
- Allows creating a new private repository on GitHub and initializing it locally.
- Aims for cross-platform compatibility (Linux, macOS, Windows).

Requires:
- Python 3.6+
- Bitwarden CLI (bws) installed and in PATH
- Git installed and in PATH
- `requests` library (`pip install requests`)
- A Bitwarden secret containing the GitHub PAT, with its ID optionally
  set in the GH_TOKEN_ID environment variable.
- BWS_ACCESS_TOKEN environment variable set for Bitwarden CLI authentication.
"""

import json
import os
import platform
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Union

# --- Configuration ---

# Default Bitwarden secret ID for the GitHub token if GH_TOKEN_ID env var isn't set
DEFAULT_GH_TOKEN_ID = "857d0c2c-cfe0-4e6d-995c-b1690020f8fb"
# Default license to fetch
DEFAULT_LICENSE_URL = "https://www.gnu.org/licenses/gpl-3.0.txt"
DEFAULT_LICENSE_NAME = "LICENSE"

# --- Helper Functions ---

def run_command(
    command: Union[str, List[str]],
    cwd: Optional[Union[str, Path]] = None,
    check: bool = True,
    capture_output: bool = True,
    env: Optional[Dict[str, str]] = None,
    shell: bool = False, # Use shell=True cautiously
) -> subprocess.CompletedProcess:
    """
    Runs a shell command using subprocess.run.

    Args:
        command: The command to run, as a string or list of strings.
        cwd: The working directory to run the command in.
        check: If True, raise CalledProcessError if the command returns non-zero exit code.
        capture_output: If True, capture stdout and stderr.
        env: Optional dictionary of environment variables.
        shell: If True, run command through the shell. Use with trusted input only.

    Returns:
        A CompletedProcess object.

    Raises:
        FileNotFoundError: If the command executable is not found.
        subprocess.CalledProcessError: If check is True and the command fails.
        Exception: For other potential subprocess errors.
    """
    if isinstance(command, str) and not shell:
        cmd_list = shlex.split(command)
    elif isinstance(command, str) and shell:
        cmd_list = command # Pass string directly to shell
    else:
        cmd_list = command

    print(f"Running command: {' '.join(cmd_list) if not shell else cmd_list}" + (f" in {cwd}" if cwd else ""))
    try:
        process = subprocess.run(
            cmd_list,
            cwd=cwd,
            check=check,
            capture_output=capture_output,
            text=True,
            env=env or os.environ,
            shell=shell, # Be careful with shell=True
        )
        if capture_output and process.stdout:
            print("Command STDOUT:\n" + process.stdout.strip())
        if capture_output and process.stderr:
            # Don't print stderr if check=True, as it will be in the exception
            if not check or process.returncode == 0:
                 print("Command STDERR:\n" + process.stderr.strip(), file=sys.stderr)

        return process
    except FileNotFoundError as e:
        print(f"Error: Command not found: {cmd_list[0] if isinstance(cmd_list, list) else cmd_list.split()[0]}. Is it installed and in PATH?", file=sys.stderr)
        raise e
    except subprocess.CalledProcessError as e:
        print(f"Error: Command failed with exit code {e.returncode}: {cmd_list}", file=sys.stderr)
        if capture_output:
            print(f"STDERR:\n{e.stderr}", file=sys.stderr)
            print(f"STDOUT:\n{e.stdout}", file=sys.stderr)
        if check: # Only raise if check was requested
             raise e
        # If check is False, return the failed process object
        return e
    except Exception as e:
        print(f"An unexpected error occurred while running command {cmd_list}: {e}", file=sys.stderr)
        raise e

def get_git_config(scope: str = 'global') -> Dict[str, str]:
    """
    Retrieves git configuration settings for the specified scope.

    Args:
        scope: 'global', 'local', or 'system'.

    Returns:
        A dictionary of git config key-value pairs. Returns empty if git fails.
    """
    config = {}
    try:
        # Use check=False because git config -l returns non-zero if no config exists
        result = run_command(['git', 'config', f'--{scope}', '-l'], check=False)
        if result.returncode == 0 and result.stdout:
            lines = result.stdout.strip().split('\n')
            for line in lines:
                if '=' in line:
                    key, value = line.split('=', 1)
                    config[key.strip()] = value.strip()
    except FileNotFoundError:
        print("Warning: 'git' command not found. Cannot retrieve git config.", file=sys.stderr)
    except Exception as e:
        print(f"Warning: Failed to get git {scope} config: {e}", file=sys.stderr)
    return config

def validate_email(email: str) -> bool:
    """Basic email format validation."""
    if re.match(r"[^@]+@[^@]+\.[^@]+", email):
        return True
    else:
        print("Invalid email address format. Please try again.", file=sys.stderr)
        return False

def choose_option(prompt: str, options: List[str]) -> Tuple[int, str]:
    """
    Presents a list of options to the user and returns the chosen index and value.
    """
    print(f"\n{prompt}")
    for i, option in enumerate(options):
        print(f"[{i}] {option}")

    while True:
        try:
            choice_str = input("Please select: ")
            choice_int = int(choice_str)
            if 0 <= choice_int < len(options):
                return choice_int, options[choice_int]
            else:
                print(f"Invalid choice. Please enter a number between 0 and {len(options) - 1}.", file=sys.stderr)
        except ValueError:
            print("Invalid input. Please enter a number.", file=sys.stderr)
        except EOFError:
            print("\nOperation cancelled by user.", file=sys.stderr)
            sys.exit(1)

def get_github_token_from_bws() -> Optional[str]:
    """
    Retrieves the GitHub PAT from Bitwarden using bws CLI.
    """
    print("Attempting to retrieve GitHub token from Bitwarden...")
    if "BWS_ACCESS_TOKEN" not in os.environ:
        print("Error: BWS_ACCESS_TOKEN environment variable not set.", file=sys.stderr)
        print("Please set it to your Bitwarden access token.", file=sys.stderr)
        return None

    gh_token_id = os.environ.get("GH_TOKEN_ID", DEFAULT_GH_TOKEN_ID)
    print(f"Using Bitwarden secret ID: {gh_token_id}")

    try:
        # Command to get the secret, output as TSV, take last line (in case of warnings), print 3rd field (password)
        # Using shell=True here because the pipe/awk logic is hard to replicate reliably with subprocess args list across platforms
        # Ensure GH_TOKEN_ID is validated or controlled if possible.
        # Alternative without shell=True requires more parsing in Python.
        command = f"bws secret get {shlex.quote(gh_token_id)} -o tsv" # Get TSV output
        result = run_command(command, check=True, capture_output=True) # Run and check

        # Parse the TSV output
        lines = result.stdout.strip().splitlines()
        if not lines:
             print("Error: No output received from 'bws secret get'.", file=sys.stderr)
             return None

        # Find the line starting with 'password:' - bws tsv format might vary
        # A more robust approach might be to parse the JSON output if TSV proves unstable
        password_line = None
        for line in reversed(lines): # Check from the end
            if line.startswith("password\t"):
                password_line = line
                break

        if not password_line:
             print("Error: Could not find 'password' field in 'bws secret get' TSV output.", file=sys.stderr)
             print("Full output:\n" + result.stdout, file=sys.stderr)
             return None

        parts = password_line.strip().split('\t')
        if len(parts) >= 2:
            token = parts[1]
            print("Successfully retrieved GitHub token from Bitwarden.")
            return token
        else:
            print(f"Error: Unexpected format in 'bws secret get' output line: {password_line}", file=sys.stderr)
            return None

    except FileNotFoundError:
        print("Error: 'bws' command not found. Is Bitwarden CLI installed and in PATH?", file=sys.stderr)
        return None
    except subprocess.CalledProcessError:
        # Error message already printed by run_command
        print("Failed to retrieve GitHub token from Bitwarden.", file=sys.stderr)
        return None
    except Exception as e:
        print(f"An unexpected error occurred while retrieving token: {e}", file=sys.stderr)
        return None

def get_user_input(prompt: str, validation_func: Optional[callable] = None, allow_empty: bool = False) -> str:
    """Gets validated user input."""
    while True:
        try:
            value = input(f"{prompt}: ").strip()
            if value or allow_empty:
                if validation_func is None or validation_func(value):
                    return value
            else:
                print("Input cannot be empty. Please try again.", file=sys.stderr)
        except EOFError:
            print("\nOperation cancelled by user.", file=sys.stderr)
            sys.exit(1)

# --- Main Actions ---

def get_repositories(token: str) -> Optional[List[str]]:
    """Fetches the list of repository full names for the authenticated user."""
    print("Fetching list of your repositories from GitHub...")
    api_url = "https://api.github.com/user/repos"
    headers = {'Authorization': f'token {token}', 'Accept': 'application/vnd.github.v3+json'}
    params = {'per_page': 100} # Fetch up to 100 repos per page
    repos = []
    page = 1

    try:
        while True:
            params['page'] = page
            response = requests.get(api_url, headers=headers, params=params, timeout=15)
            response.raise_for_status() # Raise HTTPError for bad responses (4xx or 5xx)
            data = response.json()
            if not data: # No more repos
                break
            repos.extend([repo['full_name'] for repo in data])
            if 'next' not in response.links: # Check if there's a next page
                 break
            page += 1
            api_url = response.links['next']['url'] # Follow pagination link

        print(f"Found {len(repos)} repositories.")
        return sorted(repos)
    except requests.exceptions.RequestException as e:
        print(f"Error fetching repositories from GitHub: {e}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"An unexpected error occurred while fetching repositories: {e}", file=sys.stderr)
        return None

def action_clone_repository(token: str):
    """Handles cloning an existing repository."""
    repos = get_repositories(token)
    if not repos:
        print("Could not retrieve repository list. Aborting clone.", file=sys.stderr)
        return False # Indicate failure

    index, chosen_repo_full_name = choose_option("Select a repository to clone", repos)
    repo_name = chosen_repo_full_name.split('/')[-1]
    repo_path = Path(repo_name)

    if repo_path.exists():
        print(f"Error: Directory '{repo_name}' already exists.", file=sys.stderr)
        return False

    print(f"Cloning '{chosen_repo_full_name}' into './{repo_name}'...")
    clone_url = f"https://github.com/{chosen_repo_full_name}.git" # Use standard HTTPS

    try:
        # Clone using standard HTTPS, rely on credential helper
        run_command(['git', 'clone', clone_url, repo_name])

        # Configure credential helper locally for this repo (optional, but matches original)
        # Git Credential Manager (recommended) or cache
        helper_to_set = 'manager' if platform.system() == 'Windows' else 'cache --timeout=3600'
        print(f"Configuring local credential.helper to '{helper_to_set}'...")
        run_command(['git', 'config', '--local', 'credential.helper', helper_to_set], cwd=repo_path)

        print(f"Successfully cloned '{chosen_repo_full_name}'.")
        return True # Indicate success

    except (FileNotFoundError, subprocess.CalledProcessError, Exception) as e:
        print(f"Failed to clone repository: {e}", file=sys.stderr)
        # Cleanup potentially incomplete clone directory? Maybe not, user might want to inspect.
        # if repo_path.exists():
        #     import shutil
        #     print(f"Attempting to clean up directory '{repo_name}'...")
        #     shutil.rmtree(repo_path, ignore_errors=True)
        return False

def action_create_repository(token: str, username_from_config: Optional[str]):
    """Handles creating a new GitHub repository and initializing it locally."""
    global_config = get_git_config('global')

    # --- Gather Information ---
    name = global_config.get('user.name') or get_user_input("Enter your Full Name")
    email = global_config.get('user.email') or get_user_input("Enter your Email Address", validate_email)
    # Prefer username from initial config/prompt, fallback to global git config
    username = username_from_config or global_config.get('user.github.login.name') or get_user_input("Enter your Github Username")
    repo_name = get_user_input("Enter a unique name for the new repository")

    repo_path = Path(repo_name)
    if repo_path.exists():
        print(f"Error: Directory '{repo_name}' already exists.", file=sys.stderr)
        return False

    # --- Create Remote Repository ---
    print(f"Creating new private repository '{username}/{repo_name}' on GitHub...")
    api_url = "https://api.github.com/user/repos"
    headers = {'Authorization': f'token {token}', 'Accept': 'application/vnd.github.v3+json'}
    data = {
        'name': repo_name,
        'description': 'Created with Python GitHub utility script',
        'private': True, # Defaulting to private as per original script
    }
    try:
        response = requests.post(api_url, headers=headers, data=json.dumps(data), timeout=15)
        response.raise_for_status()
        repo_data = response.json()
        print(f"Successfully created remote repository: {repo_data.get('html_url')}")
    except requests.exceptions.RequestException as e:
        print(f"Error creating repository on GitHub: {e}", file=sys.stderr)
        if hasattr(e, 'response') and e.response is not None:
             try:
                 print(f"GitHub API Response: {e.response.json()}", file=sys.stderr)
             except json.JSONDecodeError:
                 print(f"GitHub API Response (non-JSON): {e.response.text}", file=sys.stderr)
        return False
    except Exception as e:
         print(f"An unexpected error occurred during remote repo creation: {e}", file=sys.stderr)
         return False

    # --- Initialize Local Repository ---
    print(f"Initializing local repository in './{repo_name}'...")
    try:
        repo_path.mkdir()
        run_command(['git', 'init'], cwd=repo_path)

        # --- Configure Git Locally (if not set globally) ---
        print("Configuring local git settings...")
        if 'user.name' not in global_config:
            run_command(['git', 'config', '--local', 'user.name', name], cwd=repo_path)
        if 'user.email' not in global_config:
            run_command(['git', 'config', '--local', 'user.email', email], cwd=repo_path)
        # Store username used for creation if not set globally
        if 'user.github.login.name' not in global_config:
             run_command(['git', 'config', '--local', 'user.github.login.name', username], cwd=repo_path)
        # Avoid storing token in local config - use credential helper
        # if 'user.github.token' not in global_config:
        #     run_command(['git', 'config', '--local', 'user.github.token', token], cwd=repo_path)


        # --- Configure Git Globally (if not set) ---
        if 'credential.helper' not in global_config:
            helper = 'manager' if platform.system() == 'Windows' else 'cache --timeout=3600'
            print(f"Setting global credential.helper to '{helper}'...")
            run_command(['git', 'config', '--global', 'credential.helper', helper], check=False) # Don't fail if this errors

        if 'push.default' not in global_config:
            print("Setting global push.default to 'simple'...")
            run_command(['git', 'config', '--global', 'push.default', 'simple'], check=False)

        # --- Add Remote and Initial Commit ---
        # Use HTTPS URL without token, rely on credential helper
        remote_url = f"https://github.com/{username}/{repo_name}.git"
        # remote_url_with_token = f"https://{token}@github.com/{username}/{repo_name}.git" # Less secure alternative

        print(f"Adding remote origin: {remote_url}")
        run_command(['git', 'remote', 'add', 'origin', remote_url], cwd=repo_path)

        # Create README
        readme_content = f"# {repo_name}\n\nCreated by {username} via script.\n"
        (repo_path / "README.md").write_text(readme_content)
        print("Created README.md")

        # Fetch and create LICENSE
        try:
            print(f"Fetching LICENSE from {DEFAULT_LICENSE_URL}...")
            license_response = requests.get(DEFAULT_LICENSE_URL, timeout=10)
            license_response.raise_for_status()
            (repo_path / DEFAULT_LICENSE_NAME).write_text(license_response.text)
            print(f"Created {DEFAULT_LICENSE_NAME}")
        except requests.exceptions.RequestException as e:
            print(f"Warning: Failed to fetch LICENSE file: {e}", file=sys.stderr)

        # --- Git Add, Commit, Push ---
        print("Adding files and making initial commit...")
        run_command(['git', 'add', '.'], cwd=repo_path)
        run_command(['git', 'commit', '-m', 'Initial commit'], cwd=repo_path)

        print("Renaming branch to 'main'...")
        run_command(['git', 'branch', '-M', 'main'], cwd=repo_path)

        print("Pushing initial commit to origin main...")
        # This push will likely trigger the credential helper configured earlier
        run_command(['git', 'push', '--set-upstream', 'origin', 'main'], cwd=repo_path)

        print(f"\nSuccessfully created and initialized repository '{repo_name}'.")
        print(f"Local path: {repo_path.resolve()}")
        print(f"Remote URL: {remote_url}")
        return True

    except (FileNotFoundError, subprocess.CalledProcessError, Exception) as e:
        print(f"\nError during local repository initialization: {e}", file=sys.stderr)
        print("Manual cleanup of remote repo on GitHub and local directory might be required.", file=sys.stderr)
        # Optional: Attempt cleanup
        # if repo_path.exists():
        #     import shutil
        #     print(f"Attempting to clean up directory '{repo_name}'...")
        #     shutil.rmtree(repo_path, ignore_errors=True)
        # Consider API call to delete remote repo? Risky.
        return False


# --- Main Execution ---

def main():
    """Main script execution logic."""
    print("--- GitHub Repository Utility ---")

    # 1. Check Dependencies (Basic Check)
    try:
        run_command(['git', '--version'], check=True, capture_output=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        print("Error: 'git' command not found or not working. Please install Git and ensure it's in your PATH.", file=sys.stderr)
        sys.exit(1)
    try:
        run_command(['bws', '--version'], check=True, capture_output=True)
    except (FileNotFoundError, subprocess.CalledProcessError):
        print("Error: 'bws' command not found or not working. Please install Bitwarden CLI and ensure it's in your PATH.", file=sys.stderr)
        sys.exit(1)
    try:
        import requests
    except ImportError:
         print("Error: 'requests' library not found. Please install it: pip install requests", file=sys.stderr)
         sys.exit(1)


    # 2. Get GitHub Token
    github_token = get_github_token_from_bws()
    if not github_token:
        sys.exit(2)

    # 3. Get GitHub Username (primarily for repo creation context)
    git_config = get_git_config('global')
    github_username = git_config.get('user.github.login.name')
    if not github_username:
        print("\nGitHub username not found in global git config (user.github.login.name).")
        github_username = get_user_input("Please enter your Github Username")


    # 4. Choose Action
    action_index, action_name = choose_option(
        "What would you like to do?",
        ["Create a new repository", "Clone an existing repository"]
    )

    # 5. Execute Action
    success = False
    if action_index == 0: # Create
        success = action_create_repository(github_token, github_username)
    elif action_index == 1: # Clone
        success = action_clone_repository(github_token)

    # 6. Exit Status
    if success:
        print("\nOperation completed successfully.")
        sys.exit(0)
    else:
        print("\nOperation failed or was aborted.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nOperation cancelled by user (Ctrl+C).", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\nAn unexpected critical error occurred: {e}", file=sys.stderr)
        # You might want to add more detailed logging here for debugging
        # import traceback
        # traceback.print_exc()
        sys.exit(99)

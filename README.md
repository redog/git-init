git-init
========

## Prerequisites
  1. Curl - unzip - python3 - python-venv - jq - wget
  
  1. bws - bitwarden sdk (secrets manager)
  
  1. bw - bitwarden cli
    
     ```
     bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/bws-install.sh)
     bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/bw-install.sh)
     ```
     
  1. requests python module
    
     ```
     python -m venv venv
     source venv/bin/activate
     pip install requests  
     read BWS_ACCESS_TOKEN
     export BWS_ACCESS_TOKEN
     echo -n "$BWS_ACCESS_TOKEN" | secret-tool store --label="Bitwarden Access Token" bitwarden accesstoken
     ```

## Get it and init it

```
bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)
```

## Source the key initialization script so that environment variables such as `BW_SESSION` are exported to your current shell.

```
./init.sh && source ./bw-key-init.sh
```

The `bw-key-init.sh` script will automatically log in to Bitwarden using your API
key (if available) before unlocking the vault, so no manual `bw login` step is
required.

### Git Credential Helper

Use the provided `git-credential-env` script to supply your GitHub token at runtime
without storing it in git config:

```bash
mkdir -p ~/.config
cp git-credential-env ~/.config/
git config --global credential.helper '!~/.config/git-credential-env'
```

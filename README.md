git-init
========

## Prerequisites
  1. Curl - unzip - jq - git
  
  1. bws - bitwarden sdk (secrets manager)
  
  1. bw - bitwarden cli
    
     ```
     bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/bws-install.sh)
     bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/bw-install.sh)
     ```
     

## Get it and init it

```
bash <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)
```

## Source the initialization script so that environment variables such as `BW_SESSION` are exported to your current shell.

```
source ./init.sh
```

### One-liner to source from GitHub

```bash
source <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)
```

The script will automatically log in to Bitwarden using your API key (if available) before unlocking the vault, so no manual `bw login` step is required.

## Configuration

Secret IDs are normally read from `config.env` inside this repository. You can
store them elsewhere by creating `~/.git-init.env` or by setting the
`GIT_INIT_CONFIG` environment variable to the path of your preferred config
file. The scripts will use that file if present before falling back to the repo
version.
 
### Git Credential Helper

`init.sh` will automatically create the `git-credential-env` helper in
`~/.config` when it isn't found, so you generally don't need to copy it
manually. The helper supplies your GitHub token at runtime without
storing it in git config. To set it up yourself:

```bash
mkdir -p ~/.config
cp git-credential-env ~/.config/
git config --global credential.helper '!~/.config/git-credential-env'
```
The helper expects your token in the `GITHUB_ACCESS_TOKEN` environment variable
whenever Git needs authentication. Avoid setting `user.github.token` in any git
configuration; credentials are provided dynamically by the helper.

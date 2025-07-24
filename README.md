git-init
========

## Prerequisites
  1. Curl - unzip - jq - wget - git
  
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

## Source the key initialization script so that environment variables such as `BW_SESSION` are exported to your current shell.

```
./init.sh && source ./bw-key-init.sh
```

The `bw-key-init.sh` script will automatically log in to Bitwarden using your API
key (if available) before unlocking the vault, so no manual `bw login` step is
required.

git-init
========

## Prerequisites
  1. Curl - unzip - git

### Setup
Run `./setup.sh` to install the following tools if they are not already available:

  * jq - JSON processor
  * bws - Bitwarden SDK (secrets manager)
  * bw - Bitwarden CLI

## Get it and init it
### Source the initialization script so that environment variables such as `BW_SESSION` are exported to your current shell.

```
source <(curl -sS https://raw.githubusercontent.com/redog/git-init/master/init.sh)
```

The script will automatically log in to Bitwarden using your API key (if available) before unlocking the vault, so no manual `bw login` step is required.

## Configuration

Secret IDs are normally read from `config.env` inside this repository. You can
store them elsewhere by creating `~/.git-init.env` or by setting the
`GIT_INIT_CONFIG` environment variable to the path of your preferred config
file. The scripts will use that file if present before falling back to the repo
version.

### Configuration Details

The `init.sh` script requires several IDs to be set in the `config.env` file. Here's how to get them:

#### `GH_TOKEN_ID`
This is the ID of the secret in Bitwarden Secrets Manager that stores your GitHub Personal Access Token.

To get this ID, you first need to create a secret in Bitwarden Secrets Manager that contains your GitHub token. You can do this with the `bws` command:
```bash
bws secret create '{"name":"github-token","value":"YOUR_GITHUB_TOKEN","projectIds":[]}'
```
Then, you can list your secrets to get the ID:
```bash
bws secret list
```
The output will be a JSON array of your secrets. Find the one you just created and copy the `id` value.

#### `BW_API_KEY_ID`
This is the ID of the secret in Bitwarden Secrets Manager that stores your Bitwarden API Key.

Follow the same process as for `GH_TOKEN_ID` to create a secret for your Bitwarden API Key and get its ID.

#### `BWS_ACCESS_TOKEN_ID`
This is the ID of the login item in your Bitwarden vault that stores your Bitwarden Secrets Manager access token.

To get this ID, you first need to create a login item in your Bitwarden vault that contains your BWS access token. You can do this with the `bw` command:
```bash
bw create item '{"type":1,"name":"bws-access-token","login":{"uris":[{"uri":"https://vault.bitwarden.com","match":null}],"username":"bws-access-token","password":"YOUR_BWS_ACCESS_TOKEN"}}'
```
Then, you can list your vault items to get the ID:
```bash
bw list items --search bws-access-token
```
The output will be a JSON array of your vault items. Find the one you just created and copy the `id` value.

### Git Credential Helper

`init.sh` will automatically create a `git-credential-env` helper in
`~/.config` when it isn't found. The helper supplies your GitHub 
token at runtime without storing it in git config. 

The helper expects your token in the `GITHUB_ACCESS_TOKEN` environment variable
whenever Git needs authentication. Avoid setting `user.github.token` in any git
configuration; credentials are provided dynamically by the helper.

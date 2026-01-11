@{
    # Required: Bitwarden Secrets Manager ID for your GitHub Token
    # You can get this by running: bws secret list
    GH_TOKEN_ID = "your-secret-uuid-here"

    # Optional: Bitwarden API credentials for automated login
    # If these are set, the script will attempt to login automatically using the API key.
    # BW_CLIENTID = "client_id_..."
    # BW_CLIENTSECRET = "client_secret_..."
}

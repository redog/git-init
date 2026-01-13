@{
    # Secrets Manager CLI executable (Bitwarden Secrets Manager)
    BwsCliPath = 'bws'

    # bw item that contains your BWS access token (used to bootstrap bws)
    # Store the token in either:
    #   - item.notes, OR
    #   - a custom field named 'token', OR
    #   - the login password (falls back to .login.password)
    BwsTokenItem = 'Bitwarden Secrets Manager Service Account'

    # Map entries:
    # - Name: label for reporting/filtering
    # - SecretId: Secrets Manager secret id
    # - Env: hashtable of env var(s) to set
    #   Values:
    #     * '$secret' => replaced with retrieved secret
    #     * literal   => set as-is
    KeyMap = @(
        @{ Name='Mistral'    ; SecretId='f9e077a8-86e0-43d8-8fe0-b2b500f258ea' ; Env=@{ MISTRAL_API_KEY      = '$secret' } }
        @{ Name='Claude'     ; SecretId='3d9cd15a-fb36-4c99-90be-b2a8010f4709' ; Env=@{ CLAUDE_API_KEY       = '$secret' } }
        @{ Name='Gemini'     ; SecretId='6f8bdc68-6802-474f-bde5-b1690043038f' ; Env=@{ GEMINI_API_KEY       = '$secret' } }
        @{ Name='Groq'       ; SecretId='437f8d17-a314-46db-b043-b18e0110bde1' ; Env=@{ GROQ_API_KEY         = '$secret' } }
        @{ Name='Tavily'     ; SecretId='c8b5ce6a-5b35-403f-ad86-b2c70149f052' ; Env=@{ TAVILY_API_KEY       = '$secret' } }

        # LangSmith: one secret -> multiple env vars + tracing flag
        @{ Name='LangSmith'  ; SecretId='ad3f662b-9c78-4d22-9e15-b2c70147eabc' ; Env=@{
            LANGCHAIN_TRACING_V2 = 'true'
            LANGCHAIN_API_KEY    = '$secret'
            LANGSMITH_API_KEY    = '$secret'
        } }

        @{ Name='Notion'     ; SecretId='7909c25f-f3d3-44ea-8b86-aff8010d5ce9' ; Env=@{ NOTION_API_TOKEN     = '$secret' } }
        @{ Name='OpenAI'     ; SecretId='fbe0690e-fb43-4e91-b49c-b0b50039847a' ; Env=@{ OPENAI_API_KEY       = '$secret' } }
        @{ Name='GitHub'     ; SecretId='857d0c2c-cfe0-4e6d-995c-b1690020f8fb' ; Env=@{ GITHUB_ACCESS_TOKEN  = '$secret' } }
        @{ Name='Cloudflare' ; SecretId='c912c706-c8a3-4928-afa3-b064003857f6' ; Env=@{ CF_ACCESS_TOKEN      = '$secret' } }
        @{ Name='Fernet'     ; SecretId='d16db1df-6bcf-4f90-a341-b0640187c855' ; Env=@{ FN_ENC_KEY           = '$secret' } }
        @{ Name='Vault'      ; SecretId='42e1e10a-8ea9-427c-9c9e-b070013edb70' ; Env=@{ VAULT_PASSWORD       = '$secret' } }
    )
}

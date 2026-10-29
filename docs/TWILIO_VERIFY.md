# Twilio Verify SMS phone authentication

This runbook enables Twilio Verify for OLGA phone-number signup and sign-in. Microsoft Entra External ID continues to own Email OTP, Google, and Apple. Twilio generates, sends, and verifies the SMS OTP; it proves possession of a phone number only. After a successful check, OLGA Core links the normalized phone identity and issues OLGA access and refresh tokens.

Terraform owns only the Azure Container App configuration and versionless Key Vault references. Twilio accounts, Verify Services, API keys, credential values, and the OLGA JWT signing key are provisioned outside Terraform. OTP values and raw credentials must never enter source control, Terraform inputs/state/plans/outputs, GitHub variables, workflow logs, application logs, tickets, or documentation.

## Environment isolation

Create dev first and do not reuse any item in production.

| Item | dev | prd |
| --- | --- | --- |
| Twilio account/subaccount | `olga-dev` | `olga-prod` |
| Verify Service | `OLGA Dev` | `OLGA Prod` |
| API key | `olga-core-verify-dev` | `olga-core-verify-prod` |
| Verify Service SID | distinct `VA...` | distinct `VA...` |
| Azure Key Vault | dev vault | production vault |
| OLGA signing key | dev-only | production-only |

Use an upgraded, funded Twilio parent account with an approved Primary Compliance Profile. A subaccount may display a zero balance because usage is charged to the parent balance. Use the subaccount's own Account SID and API key for Core.

## 1. Configure Twilio dev

1. Select the `olga-dev` subaccount and record its `AC...` Account SID securely.
2. Under **Identity > Verify > Services**, create `OLGA Dev` with SMS, a six-digit code, the do-not-share warning, and Fraud Guard at Standard protection.
3. Record the non-secret `VA...` Verify Service SID.
4. Under **Verify > Settings > Geo permissions**, configure Malaysia for SMS with Fraud Guard monitoring and disable destinations OLGA does not serve.
5. Create the US1 restricted API key `olga-core-verify-dev` with only `twilio/verify/verification/create` and `twilio/verify/verification-check/create`. If restricted keys are unavailable, use a Standard key. Never use a Main key or the master Auth Token.
6. Save the `SK...` key SID and its one-time secret directly into the approved credential handoff. Do not paste them into chat or a command line.
7. Twilio's Verify code-validity setting must match the configured 300 seconds. If the Console cannot set five minutes, have an authorized account owner request it from Twilio Support before customer testing.

## 2. Provision the dev Key Vault secrets

Configure these protected GitHub Environment secrets in `dev` before Twilio is enabled:

| GitHub Environment secret | Key Vault secret name | Value source |
| --- | --- | --- |
| `TWILIO_API_KEY_SECRET` | `twilio-api-key-secret` | API key secret shown once at creation |
| `PHONE_AUTH_JWT_SIGNING_KEY` | `phone-auth-jwt-signing-key` | independently generated high-entropy OLGA signing key |

While Twilio is disabled, run **Twilio Verify - Configure Key Vault Credentials** from `develop`, select `dev`, and enter the exact confirmation `APPLY olga-twilio-credentials-dev`. The protected workflow uses the existing dev Azure OIDC identity and writes two new secret versions through the Azure control plane. That identity must retain the control-plane `Microsoft.KeyVault/vaults/secrets/write` permission. The workflow does not pass values to Terraform, create an artifact, or print credentials, and it shares the environment's Terraform apply concurrency lock. Terraform references `${key_vault_uri}secrets/<name>` without a version. The existing `id-olga-core-dev` identity and its existing Key Vault Secrets User assignment resolve them at runtime.

Do not create a Terraform variable, tfvars entry, workflow variable, output, or Terraform-managed AzAPI/Key Vault resource containing these values. GitHub Environment secrets are used only by the protected credential workflow. Production requires new provider credentials in `prd` and the confirmation `APPLY olga-twilio-credentials-prd` from `main`.

## 3. Enable dev through GitHub

In the `dev-plan` GitHub Environment, create the non-secret variable `TWILIO_VERIFY` using the actual dev Account SID, API Key SID, and Verify Service SID:

```json
{"enabled":true,"account_sid":"ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx","api_key_sid":"SKxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx","verify_service_sid":"VAxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx","default_country_code":"MY","token_ttl_seconds":300}
```

Replace all three example identifiers; do not copy them literally. The workflow maps the object to `TF_VAR_twilio_verify`. If the variable is absent, Terraform uses the disabled default and creates no Twilio secret reference. Production remains disabled until an independently reviewed `prd-plan` variable is configured.

Review the dev saved plan before apply. The expected change is a new Core Container App revision containing two external Key Vault secret references, two secret-backed environment variables, and the non-secret settings below:

```text
Twilio__Enabled=true
Twilio__AccountSid=<dev AC SID>
Twilio__ApiKeySid=<dev SK SID>
Twilio__VerifyServiceSid=<dev VA SID>
Twilio__DefaultCountryCode=MY
Twilio__TokenTtlSeconds=300
PhoneAuthentication__Issuer=olga-phone-auth-dev
PhoneAuthentication__Audience=olga-mobile-dev
PhoneAuthentication__AccessTokenMinutes=15
PhoneAuthentication__RefreshTokenDays=30
```

No inbound Twilio webhook is required. Static inspection shows no Terraform-managed NSG, route table, NAT gateway, Azure Firewall, or Container Apps egress rule on the workload subnet, so Core's existing outbound HTTPS path does not prohibit `verify.twilio.com:443`.

## 4. Application and database work still required

Infrastructure enablement does not implement phone authentication. Before exposing the option, the Core and database repositories must provide reviewed changes that:

- add versioned `/v1` send/check endpoints and require `Idempotency-Key` for mutations;
- normalize phone numbers to E.164 and rate-limit by phone, device/session, and source address without logging raw OTPs;
- call Twilio Verify using parameterized server-side configuration and treat approval as phone possession only;
- link one verified phone identity to the correct OLGA member under explicit conflict/recovery rules;
- issue and validate OLGA JWT access/refresh tokens using the dedicated issuer, audience, signing key, expiry, rotation, and revocation rules;
- add PostgreSQL migrations and repositories for phone identities and hashed/revocable refresh sessions, following lower-snake-case naming, identity keys, `timestamptz`, and `row_version` concurrency requirements; and
- add mobile UI, secure token storage, account recovery, resend throttling, and error handling.

Do not enable production until those changes and the complete dev flow have been verified with real Malaysian test numbers.

## API-key rotation

The API Key SID and secret are a pair, but they travel through separate non-secret and secret channels. Until Core supports simultaneous primary and secondary credentials, use this controlled-outage sequence so replicas never serve a mismatched pair:

1. In the matching Twilio subaccount, create a replacement restricted key with the same two Verify permissions. Keep the old key active.
2. Set `TWILIO_VERIFY.enabled` to `false`, review and apply the normal Terraform plan, and verify the phone-auth endpoints are unavailable.
3. Update `TWILIO_API_KEY_SECRET` in the matching protected GitHub Environment and rerun **Twilio Verify - Configure Key Vault Credentials**. Keep `PHONE_AUTH_JWT_SIGNING_KEY` unchanged. Then update `api_key_sid` in the matching `TWILIO_VERIFY` plan variable and set `enabled` back to `true`.
4. Review and apply the normal Terraform plan. The resulting Core revision resolves the replacement secret and carries the replacement SID. Verify both send and check operations across all replicas.
5. Delete the old Twilio API key only after the replacement succeeds. Never fall back to the master Auth Token.

Rotate `phone-auth-jwt-signing-key` only through a coordinated application rotation that supports validation of tokens signed by the retiring key until their permitted lifetime ends.

## Rollback

Set the environment's `TWILIO_VERIFY` variable to the disabled object and run the normal reviewed plan/apply:

```json
{"enabled":false,"account_sid":null,"api_key_sid":null,"verify_service_sid":null,"default_country_code":"MY","token_ttl_seconds":300}
```

This removes the two Twilio/phone-auth secret references and secret-backed environment variables from Core and sets `Twilio__Enabled=false`. It does not delete the external Key Vault secret values, Twilio API key, or Verify Service. Disable or revoke those separately only when incident scope requires it and recovery implications have been reviewed.

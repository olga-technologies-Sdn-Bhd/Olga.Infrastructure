# Apple federation for Microsoft Entra External ID

This runbook adds Apple to the existing environment-specific customer user flow without replacing or depending on Email OTP, Google, or any other configured provider. Apple is browser-delegated federation; the mobile application continues to use the existing Entra authority, authorization-code flow with PKCE, native callback, scopes, token exchange, secure storage, and sign-out behavior.

## Ownership and boundaries

Apple Developer configuration is performed outside Terraform. The Apple `.p8` private key is supplied only to the protected Apple workflow at runtime and must never enter Terraform variables, plans, state, outputs, workflow summaries, artifacts, application configuration, or mobile builds.

`scripts/bootstrap-apple-identity-provider.ps1` creates or rotates only the Apple provider and adds it to the existing `olga_signup_signin_<environment>` user flow. Before mutation it records every existing identity-provider association; after mutation it verifies Apple is present and every original association remains. It does not require or update Email OTP, Google, applications, service principals, attributes, permissions, or native-authentication settings.

Microsoft Graph currently exposes Apple provider management for External ID tenants through the beta API. The script confines beta calls to the Apple provider and its user-flow association. Reassess v1.0 availability before production rollout or future API-version changes.

## Apple Developer configuration

Use the mobile application's existing explicit iOS bundle identifier as the Primary App ID and enable **Sign in with Apple**. The Primary App ID and Apple Team ID may be shared when dev and prd use the same iOS bundle identifier. Keep each environment's Service ID, signing key, Entra tenant, domains, and return URLs independent.

Recommended Service IDs:

```text
com.olga.connect.auth.dev
com.olga.connect.auth.prd
```

For each Service ID, select the OLGA Primary App ID and configure only that environment's lowercase Entra domains and federation return URLs:

```text
<tenant-subdomain>.ciamlogin.com
<tenant-id>.ciamlogin.com

https://<tenant-id>.ciamlogin.com/<tenant-id>/federation/oauth2
https://<tenant-id>.ciamlogin.com/<tenant-subdomain>/federation/oauth2
https://<tenant-subdomain>.ciamlogin.com/<tenant-id>/federation/oauth2
```

Do not add `olga-dev://auth` or `olga-dev://auth/` to Apple Developer. Apple returns to Entra through the HTTPS federation URLs above; Entra then returns to the mobile app through the separately registered public-client callback. For dev, that callback is exactly `olga-dev://auth` with no trailing slash. The iOS app claims only the `olga-dev` URL scheme.

Create a separate **Sign in with Apple** key for the environment when Apple account limits permit it. Record the non-secret Team ID and Key ID, download the `.p8` file once, and place it immediately in the approved secret manager. Leave the optional server-to-server notification endpoint empty until OLGA implements a dedicated HTTPS endpoint that validates Apple's signed notifications.

## GitHub Environment configuration

Configure these independently in protected GitHub Environments `dev` and `prd`:

| Name | GitHub type | Value |
| --- | --- | --- |
| `APPLE_SERVICE_ID` | Variable | Matching environment's Apple Service ID |
| `APPLE_TEAM_ID` | Variable | Apple Developer Team ID |
| `APPLE_KEY_ID` | Variable | Matching Apple signing-key ID |
| `APPLE_PRIVATE_KEY_P8` | Secret | Complete contents of the matching `.p8` file |

The existing `EXTERNAL_DIRECTORY_CLIENT_ID`, `EXTERNAL_TENANT_ID`, and `EXTERNAL_TENANT_SUBDOMAIN` variables are reused. The OIDC application requires the existing Microsoft Graph application permissions `IdentityProvider.ReadWrite.All`, `Organization.Read.All`, and `EventListener.ReadWrite.All`, with tenant-wide admin consent.

Enter `APPLE_PRIVATE_KEY_P8` as the actual multiline file contents, including the exact `BEGIN PRIVATE KEY` and `END PRIVATE KEY` lines. Do not store a file path, base64-encode the whole PEM file, or replace line breaks with the two literal characters `\n`. The bootstrap validates the PKCS#8 elliptic-curve PEM, extracts its base64 payload for Graph's `certificateData` property, and never emits either representation. Graph failures expose only the service's error code and a bounded, private-key-redacted message.

## Configure dev

Run only from `develop`:

```powershell
gh workflow run apple-identity-provider-configure.yml `
  --ref develop `
  -f environment=dev `
  -f 'confirmation=APPLY olga-apple-identity-provider-dev'
```

The workflow creates or rotates Apple, associates the provider object ID returned by Graph with `olga_signup_signin_dev`, verifies every pre-existing provider remains, and publishes only that non-secret ID.

Test on a physical iPhone using both **Share My Email** and **Hide My Email**. Confirm the hosted user flow returns through the existing dev callback, obtains Entra tokens through PKCE, restores and refreshes the session, signs out correctly, and does not expose the private key, authorization code, or tokens. Re-test every pre-existing sign-in method independently.

## Configure prd

After dev validation and approval, create the independent prd Apple Service ID and signing key, configure the prd GitHub Environment values, and run only from `main`:

```powershell
gh workflow run apple-identity-provider-configure.yml `
  --ref main `
  -f environment=prd `
  -f 'confirmation=APPLY olga-apple-identity-provider-prd'
```

Never copy the dev Service ID, key, private key, Entra domain, or return URL into prd. Microsoft requires Apple federation credential renewal within six months. Before that deadline, rerun only the matching environment's Apple workflow with the still-valid `.p8` key. If the Apple key was revoked or replaced, update both `APPLE_PRIVATE_KEY_P8` and `APPLE_KEY_ID` first. Record the renewal owner and due date outside the repository; never store the private key here.

## Terraform source of truth

`bootstrap/external-directory` accepts the optional non-secret `apple_identity_provider_id`. After Apple is configured, use the exact provider object ID printed by the matching workflow on any later directory-root Terraform plan so that a future user-flow update retains Apple. The private key must never be passed to Terraform.

The React Native/Expo handoff, including the optional `domain_hint=apple` route and the rule that no Apple identifier or credential is added to the mobile environment, is maintained in [MOBILE_ENTRA_EXTERNAL_ID.md](MOBILE_ENTRA_EXTERNAL_ID.md#mobile-ui-provider-contract).

Microsoft references:

- [Add Apple as an identity provider](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-apple-federation-customers)
- [Apple identity provider through Microsoft Graph beta](https://learn.microsoft.com/en-us/graph/api/identitycontainer-post-identityproviders?view=graph-rest-beta)
- [Identity providers for external tenants](https://learn.microsoft.com/en-us/entra/external-id/customers/concept-authentication-methods-customers)

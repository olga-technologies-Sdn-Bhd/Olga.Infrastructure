# Microsoft Entra External ID email OTP

This runbook configures Microsoft Entra External ID as the identity provider for the OLGA React Native/Expo mobile application. The supported external environments are exactly `dev` and `prd`; the established internal Terraform production value remains `prod`. Use a separate external tenant for each environment. Never copy customer identities, tokens, personal data, redirect URIs, or deployment credentials between them.

Microsoft Entra owns OTP generation, delivery, validation, expiration, retry behavior, customer identity lifecycle, access tokens, refresh tokens, and sessions. OLGA must not generate, send, log, persist, or validate OTP values.

Core API, NLP API, Swagger, health endpoints, and existing development identity shortcuts remain unauthenticated for this MVP. A mobile access token may be sent in the `Authorization` header, but Core currently ignores it. The token does not protect either API until the deferred work in [SECURITY_DEBT.md](SECURITY_DEBT.md) is completed.

## Ownership and limitations

The isolated `bootstrap/external-tenant` Terraform root creates the External ID tenant resource through the repository's existing AzAPI provider. It uses Microsoft's preview `Microsoft.AzureActiveDirectory/ciamDirectories@2023-05-17-preview` resource, separate state per environment, and `prevent_destroy`. The manual-only `.github/workflows/bootstrap-dev-external-id.yml` workflow produces a guarded dev plan and does not run on pushes or pull requests. Microsoft requires a delegated user token for initial tenant creation, so GitHub OIDC cannot perform the apply; an authorized user performs that one-time apply locally.

After the tenant exists, `bootstrap/external-directory` manages the API and public-mobile registrations, service principals, native redirect URI, delegated API scope, preauthorization, tenant-wide delegated permission grant, and the email-OTP customer user flow associated with the mobile application. It uses the AzureAD and Microsoft Graph providers against the external tenant while retaining state in the management subscription. No application secret or certificate is created. The main Terraform root consumes the generated non-secret object and emits mobile and future Core configuration.

Microsoft references:

- [Create an external-tenant sign-up and sign-in user flow](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-user-flow-sign-up-sign-in-customers)
- [Create a CIAM directory with Terraform AzAPI](https://learn.microsoft.com/en-us/azure/templates/microsoft.azureactivedirectory/ciamdirectories)
- [Associate an application with a user flow](https://learn.microsoft.com/en-us/entra/external-id/customers/how-to-user-flow-add-application)
- [Register an application](https://learn.microsoft.com/en-us/graph/auth-register-app-v2)
- [Expose a delegated web API scope](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-configure-app-expose-web-apis)
- [Redirect URI restrictions](https://learn.microsoft.com/en-us/entra/identity-platform/reply-url)

## Required operator roles

Use least privilege and separate administrators for dev and prd where practical.

- Tenant creation: an account permitted to create an external tenant and associate billing/subscription details.
- User flow and identity-provider configuration: Microsoft Graph delegated `EventListener.ReadWrite.All` plus `External ID User Flow Administrator`, or a more privileged approved role.
- Application registrations, scopes, and delegated permissions: `Application Administrator` or `Cloud Application Administrator`.
- Tenant-wide admin consent: `Cloud Application Administrator`, `Privileged Role Administrator`, or another role authorized by the tenant's consent policy.

Do not use a customer account as an administrator. Protect administrator accounts with the organization's standard strong authentication and emergency-access controls.

## Environment inventory

| Item | dev | prd |
| --- | --- | --- |
| External tenant | OLGA dev external tenant | OLGA prd external tenant |
| User flow | `olga_signup_signin_dev` | `olga_signup_signin_prd` |
| Mobile registration | `olga_mobile_dev` | `olga_mobile_prd` |
| API registration | `olga_api_dev` | `olga_api_prd` |
| Redirect URI example | `olga-dev://auth` | `olga://auth` |
| Main Terraform state key | `olga/dev.tfstate` | `olga/prd.tfstate` |
| Tenant bootstrap state key | `olga/external-id/dev.tfstate` | `olga/external-id/prd.tfstate` |
| Directory bootstrap state key | `olga/external-directory/dev.tfstate` | `olga/external-directory/prd.tfstate` |

The examples deliberately use different redirect schemes. The released mobile bundle/package configuration must claim only its matching scheme. Never register the dev callback on the prd application or the prd callback on the dev application.

## One-time procedure per environment

Complete every step once for dev, then repeat it independently for prd with the matching names and state.

### 1. Create and select the external tenant

1. Copy the matching files under `bootstrap/external-tenant`, replace placeholders, initialize the matching backend, review the saved plan, and apply it.
2. Record the `tenant_id`, `tenant_subdomain`, `tenant_primary_domain`, `tenant_data_location`, and `tenant_authority` outputs.
3. In the Microsoft Entra admin center, use the directory switcher and confirm the output tenant ID before every later change.
4. For dev, do not import production customers or use production/personal data. Keep customer identities isolated in the selected tenant.

The tenant bootstrap deployment identity requires the approved tenant-creation role plus Azure permission to create the resource group and CIAM resource. Register the `Microsoft.AzureActiveDirectory` resource provider in the target subscription before the first plan if it is not already registered. Because the ARM resource uses a preview API, review Microsoft release notes before provider/API upgrades. Terraform is prevented from destroying the tenant resource.

### 2. Create the directory applications and user flow with Terraform

Run `bootstrap/external-directory` once with an administrator signed into the new external tenant. It creates:

- `olga_api_<environment>` as a single-tenant API registration and service principal;
- `api://<api-client-id>` and the enabled delegated `access_as_user` scope using access-token version 2;
- `olga_mobile_<environment>` as a single-tenant public-client registration and service principal;
- the exact environment-specific native redirect URI;
- the matching API permission, API preauthorization, and tenant-wide delegated permission grant;
- `olga_signup_signin_<environment>` with self-service sign-up, `EmailOtpSignup-OAUTH`, the hidden verified email attribute, an optional visible display-name field, and only the matching mobile application association.

The registrations and flow are protected with `prevent_destroy`. Terraform creates no client secret or certificate. The caller must have permission to manage applications, grant tenant-wide consent, and manage authentication events flows in the external tenant. Do not enable email-and-password or configure Twilio, Auth0, SendGrid, Azure Communication Services, or an OLGA OTP service. Microsoft manages code generation, email delivery, verification, expiration, throttling/retries, and account creation. Do not add JWT middleware or endpoint authorization to Core or NLP in this task.

At runtime request `openid profile email offline_access api://<api-client-id>/access_as_user`. The OpenID scopes are protocol scopes requested by the client. PKCE is performed by the mobile authentication library during the authorization-code exchange.

### 3. Test before publishing values

Use **Run user flow** in the matching external tenant and verify:

1. A new test customer can request and submit an email OTP and is created in that tenant.
2. The same customer can sign in again with a new email OTP.
3. The hosted page redirects only to the matching mobile URI.
4. Authorization Code with PKCE returns tokens without a client secret.
5. The requested delegated scope is `api://<matching-api-client-id>/access_as_user`.
6. The access-token audience matches the API, and the issuer exactly matches the selected tenant's OpenID discovery metadata.
7. No OTP, access token, refresh token, authorization code, or customer record appears in Terraform state, application logs, analytics, or PostgreSQL.

Delete disposable test customers according to the tenant's test-data policy. Never run prd testing with a dev callback or a copied dev identity.

## Terraform inputs

Populate the following non-secret object separately for each state. Examples are in `environments/dev.external-identity.tfvars.example` and `environments/prd.external-identity.tfvars.example`. The prd example correctly retains `environment = "prod"` because that is the established internal Terraform value.

```hcl
external_identity = {
  tenant_id             = "<external-tenant-id>"
  tenant_subdomain      = "<external-tenant-subdomain>"
  tenant_primary_domain = "<external-tenant-primary-domain>"
  location              = "<external-tenant-location>"
  mobile_redirect_uri   = "<environment-specific-mobile-redirect-uri>"
  mobile_client_id      = "<matching-mobile-application-client-id>"
  api_client_id         = "<matching-api-application-client-id>"
}
```

For CI, store the same object as a non-secret JSON/HCL value in the matching `dev`, `dev-plan`, `prd`, and `prd-plan` GitHub Environment variable named `EXTERNAL_IDENTITY`. Keep the two values independent. Do not store Graph access tokens or confidential credentials there.

## Terraform outputs and mobile use

Terraform emits these non-secret values:

- `EXPO_PUBLIC_ENTRA_CLIENT_ID`
- `EXPO_PUBLIC_ENTRA_TENANT_ID`
- `EXPO_PUBLIC_ENTRA_AUTHORITY`
- `EXPO_PUBLIC_ENTRA_REDIRECT_URI`
- `EXPO_PUBLIC_OLGA_API_SCOPE`
- `AzureAd__Instance`
- `AzureAd__TenantId`
- `AzureAd__ClientId`
- `AzureAd__Audience`
- `AzureAd__RequiredScope`
- `AzureAd__Issuer`

Copy the five `EXPO_PUBLIC_*` values only to the matching mobile build environment. `EXPO_PUBLIC_*` is visible to every app user and therefore must never contain a client secret, Graph credential, OTP, access token, or refresh token.

The mobile application must store access and refresh tokens in OS-backed secure storage such as iOS Keychain or Android Keystore-backed storage. Do not store tokens in AsyncStorage, ordinary SQLite, logs, crash reports, or analytics.

The `AzureAd__*` outputs are reserved for the later Core API enforcement work. Do not inject them into the current application merely to imply protection that does not exist.

The mobile authority uses `https://<tenant-subdomain>.ciamlogin.com/`. Before future API enforcement, compare `AzureAd__Issuer` with the `issuer` in that tenant's OpenID discovery document and use the discovery value as authoritative.

The root Terraform `tenant_id` identifies the Entra tenant that contains the Azure subscription. `external_identity.tenant_id` identifies the separate customer external tenant. Likewise, root `location` is the Azure resource region while `external_identity.location` records the external tenant creation location. Do not substitute either pair.

## Mobile runtime sequence

1. The user selects email login and the mobile app opens the Microsoft-hosted user flow in the system browser.
2. The customer enters an email address; Entra generates and sends the OTP.
3. The customer submits the OTP directly to Entra; Entra validates it and manages expiration/retries.
4. Entra creates or resolves the customer identity and redirects only to the registered environment-specific callback.
5. The public mobile client exchanges the authorization code using PKCE and no client secret.
6. The mobile app stores tokens in OS-backed secure storage.
7. The mobile app may send the access token as a Bearer token to Core API.
8. Core API currently ignores that header, and Core/NLP remain directly callable without authentication until the deferred security work is implemented.

## Current safeguards and gaps

- Each environment already has isolated Azure resource names/state, an Application Insights resource, Log Analytics, and optional budget alerts.
- Core and NLP monitoring remains independent because each environment is deployed from its own state and resource group.
- Request-size limits and rate limiting are not added here because the current platform has no approved shared enforcement component and application behavior must remain unchanged.
- Application code and telemetry configuration must redact `Authorization`, access/refresh tokens, authorization codes, OTP values, and mask email/mobile values. Terraform does not ingest those values.
- Swagger remains reachable without a token and must be described operationally as **unauthenticated during the temporary MVP phase**.
- Monitor Core/NLP request volume and failures, plus NLP latency/failures, in each environment's Application Insights. Alert thresholds remain an operator decision based on observed MVP traffic.

No OTP or token value belongs in PostgreSQL, Terraform variables, Terraform outputs, state, plan artifacts, logs, tickets, or chat.

## Validation and deployment commands

These commands are the required verification path; they were not run while preparing this change.

Focused local validation (does not deploy):

```powershell
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate -no-color
terraform -chdir=bootstrap/external-tenant fmt -check
terraform -chdir=bootstrap/external-tenant init -backend=false -input=false
terraform -chdir=bootstrap/external-tenant validate -no-color
tflint --init
tflint --recursive --format compact
trivy config --exit-code 1 --severity HIGH,CRITICAL --format table .
```

Create the dev External ID tenant first. GitHub Actions can check the plan: open **Actions**, select **External ID - Plan Dev Tenant Bootstrap**, choose **Run workflow**, enter `PLAN olga-connect-dev`, and run it from the reviewed branch. The workflow uses the protected `dev` GitHub Environment, creates a saved plan, and rejects deletes and resources outside the bootstrap boundary. It intentionally does not apply because the initial CIAM tenant API requires delegated user authentication.

Configure these non-secret variables on the `dev` GitHub Environment before dispatching the workflow: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, and `TFSTATE_CONTAINER`. These are the same Azure identity variables used by the regular infrastructure action; the bootstrap workflow additionally verifies the approved dev subscription and management tenant. The OIDC identity must trust the `dev` environment subject and have access to the state container, resource group creation, CIAM directory creation, and resource-provider registration.

Apply locally with an authorized Tenant Creator account:

```powershell
Copy-Item bootstrap/external-tenant/dev.tfvars.example bootstrap/external-tenant/dev.tfvars
Copy-Item bootstrap/external-tenant/backend-dev.hcl.example bootstrap/external-tenant/backend-dev.hcl
terraform -chdir=bootstrap/external-tenant init -input=false -reconfigure -backend-config=backend-dev.hcl
terraform -chdir=bootstrap/external-tenant plan -input=false -lock-timeout=5m -var-file=dev.tfvars -out=dev-tenant.tfplan
terraform -chdir=bootstrap/external-tenant apply -input=false -lock-timeout=10m dev-tenant.tfplan
terraform -chdir=bootstrap/external-tenant output
```

Create the directory applications using the existing state storage and a delegated administrator session. Both tenant logins are required: the management tenant owns the state account, while the External ID tenant owns the directory objects.

```powershell
az login --tenant 9972baa6-9591-43d7-8b13-59da8e6f1a72
az login --tenant d6b05a66-a3b7-442c-b56f-d4d7a9e154ba --allow-no-subscriptions
az account set --subscription e0bb013f-a8af-4d60-9c5b-0140b361f257

Copy-Item bootstrap/external-directory/dev.tfvars.example bootstrap/external-directory/dev.tfvars
Copy-Item bootstrap/external-directory/backend-dev.hcl.example bootstrap/external-directory/backend-dev.hcl
terraform -chdir=bootstrap/external-directory init
terraform -chdir=bootstrap/external-directory plan -input=false -lock-timeout=5m -var-file=dev.tfvars -out=dev-directory.tfplan
terraform -chdir=bootstrap/external-directory apply -input=false -lock-timeout=10m dev-directory.tfplan
$externalIdentity = terraform -chdir=bootstrap/external-directory output -raw external_identity_json
```

Store `$externalIdentity` as the non-secret GitHub Environment variable named `EXTERNAL_IDENTITY` in both `dev-plan` and `dev`. Do not create a variable named `TF_VAR_external_identity`; the workflow maps `EXTERNAL_IDENTITY` to that process variable. Then run the normal dev workflow from `develop`.

For optional local main-stack planning, place the same values in the ignored `environments/dev.external-identity.tfvars` file:

```powershell
Copy-Item environments/dev.external-identity.tfvars.example environments/dev.external-identity.tfvars
terraform init -input=false -reconfigure -backend-config=backend.hcl
terraform plan -input=false -lock-timeout=5m -var-file=environments/dev.external-identity.tfvars -out=dev.tfplan
terraform apply -input=false -lock-timeout=10m dev.tfplan
```

Production tenant creation and the main production deployment are manual-only. Use the existing external name `prd`; the main prd example retains Terraform's internal `environment = "prod"` value:

```powershell
Copy-Item bootstrap/external-tenant/prd.tfvars.example bootstrap/external-tenant/prd.tfvars
Copy-Item bootstrap/external-tenant/backend-prd.hcl.example bootstrap/external-tenant/backend-prd.hcl
terraform -chdir=bootstrap/external-tenant init -input=false -reconfigure -backend-config=backend-prd.hcl
terraform -chdir=bootstrap/external-tenant plan -input=false -lock-timeout=5m -var-file=prd.tfvars -out=prd-tenant.tfplan
terraform -chdir=bootstrap/external-tenant apply -input=false -lock-timeout=10m prd-tenant.tfplan

Copy-Item bootstrap/external-directory/prd.tfvars.example bootstrap/external-directory/prd.tfvars
Copy-Item bootstrap/external-directory/backend-prd.hcl.example bootstrap/external-directory/backend-prd.hcl
terraform -chdir=bootstrap/external-directory init -input=false -reconfigure -backend-config=backend-prd.hcl
terraform -chdir=bootstrap/external-directory plan -input=false -lock-timeout=5m -var-file=prd.tfvars -out=prd-directory.tfplan
terraform -chdir=bootstrap/external-directory apply -input=false -lock-timeout=10m prd-directory.tfplan

Copy-Item environments/prd.external-identity.tfvars.example environments/prd.external-identity.tfvars
.\scripts\bootstrap-state.ps1 -SubscriptionId '<prd-subscription-id>' -Location '<approved-location>' -Environment prd -StorageAccountName '<state-account>' > backend-prd.hcl
terraform init -input=false -reconfigure -backend-config=backend-prd.hcl
terraform plan -input=false -lock-timeout=5m -var-file=environments/prd.external-identity.tfvars -out=prd.tfplan
terraform apply -input=false -lock-timeout=10m prd.tfplan
```

The preferred main-stack deployment path is the protected GitHub workflow after configuring the matching GitHub Environment variables. Dev may run automatically from `develop`; prd is manual-only and must be dispatched from the reviewed `main` ref:

```powershell
gh workflow run terraform-validate-plan-apply.yml --ref develop -f environment=dev
gh workflow run terraform-validate-plan-apply.yml --ref main -f environment=prd
```

The workflow generates a fresh saved plan, applies only that plan, and requires the configured production approval. Never reuse a plan across environments.

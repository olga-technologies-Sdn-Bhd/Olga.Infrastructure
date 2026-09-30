# OLGA Connect Azure infrastructure

Terraform project for isolated OLGA Connect development and production environments. GitHub uses `dev` and `prd`; Terraform retains its established internal values `dev` and `prod`.

GitHub Actions validation, planning, deployment, environment setup, and incident guidance are documented in [docs/TERRAFORM_CI_CD.md](docs/TERRAFORM_CI_CD.md). Microsoft Entra External ID Email OTP and Google setup is documented in [docs/ENTRA_EXTERNAL_ID.md](docs/ENTRA_EXTERNAL_ID.md); the mobile integration steps are in [docs/MOBILE_ENTRA_EXTERNAL_ID.md](docs/MOBILE_ENTRA_EXTERNAL_ID.md), with the accepted temporary unauthenticated-API risk in [docs/SECURITY_DEBT.md](docs/SECURITY_DEBT.md).

## Provisioned baseline

- Resource group, mandatory tags, monthly budget alerts
- Log Analytics and Application Insights
- Azure Container Registry with managed-identity image pulls
- VNet-integrated Container Apps and private-endpoint subnets
- PostgreSQL 17 Flexible Server with private application connectivity, IP-restricted DBeaver access, Microsoft Entra administration, 7-day development backup, `vector`, and `pg_stat_statements`
- Private Key Vault and Blob Storage with purpose-specific containers
- Optional Service Bus Standard queues with duplicate detection and dead-letter behavior
- Core and NLP APIs with external HTTPS ingress
- Always-on NLP PostgreSQL polling worker with managed-identity access to ACR, Key Vault, and Azure OpenAI
- Optional SignalR, Notification Hubs, Content Safety, Azure OpenAI, API Management, and Static Web Apps

## Prerequisites

- Terraform 1.9 or later
- Azure CLI authenticated to the target tenant
- An approved Azure subscription and deployment region
- Contributor plus User Access Administrator permissions for the initial deployment
- Remote-state storage bootstrapped once

Terraform grants every principal listed for the active environment in `platform_administrator_principal_ids_by_environment` resource-group `Contributor` plus the data-plane roles required by the provisioned services: monitoring read, ACR push/delete, Key Vault administration, Blob data ownership, and—when enabled—Service Bus, Content Safety, Azure OpenAI, SignalR, and Notification Hubs administration. PostgreSQL data access remains controlled by `postgres_access_by_environment.entra_admin`. These assignments do not bypass private endpoints, service firewalls, or IP allowlists. The Terraform deployment identity needs `User Access Administrator` (or `Owner`) to create the assignments.

## First development deployment

For local deployment, create `olga-connect-dev.auto.tfvars` with the required non-secret values declared in `variables.tf`. Terraform loads this file automatically, and Git ignores it.

External tenant creation is included in `bootstrap/external-tenant`. The manual **External ID - Plan Dev Tenant Bootstrap** workflow performs a guarded plan; Microsoft requires the initial tenant creation apply to use a delegated user token, so that one-time apply runs locally. After the tenant exists, the protected **External ID Directory - Configure** workflow uses an environment-specific GitHub OIDC application to create or rotate the Google provider and associate it with the existing customer user flow through Microsoft Graph. It verifies that Email OTP remains associated and does not run Terraform or modify the existing applications, service principals, owners, attributes, or native-authentication settings. The Google secret is read only from the matching GitHub Environment secret and never enters Terraform. Production uses an independent tenant, OIDC identity, Google credential, and GitHub Environment configuration.

```powershell
.\scripts\bootstrap-state.ps1 `
  -SubscriptionId 'e0bb013f-a8af-4d60-9c5b-0140b361f257' `
  -Location 'malaysiawest' `
  -Environment 'dev' `
  -StorageAccountName '<globally-unique-state-account>' > backend.hcl

# Create olga-connect-dev.auto.tfvars and fill its required non-secret values.

terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

The initial dev configuration uses a $50 monthly budget with alerts at 50%, 80%, and 100%; a December 1, 2026 review date; PostgreSQL `B_Standard_B1ms`; 32 GiB database storage; and 0.1 GB/day telemetry caps. Azure OpenAI and NLP application delivery are enabled; Service Bus remains disabled because the NLP worker polls PostgreSQL. API Management, Static Web Apps, Content Safety, SignalR, and Notification Hubs remain disabled.

The first apply uses Microsoft's public Container Apps bootstrap image. Application repositories own subsequent immutable image revisions; Terraform owns identities, secrets, registry authentication, ingress, and ports. Core and NLP are independently configurable and both use port `8080` by default:

```hcl
core_application_delivery_enabled = true
core_health_probes_enabled         = true
nlp_application_delivery_enabled  = true
nlp_health_probes_enabled          = true
```

The infrastructure apply creates one deployment identity per repository and trusts only that repository's immutable subject for the matching GitHub Environment. Core and NLP receive `AcrPush`. The Core deployment identity receives `Container Apps Contributor` scoped only to the Core API, while the NLP deployment identity receives `Container Apps Contributor` scoped separately to both the NLP API and NLP worker. The database deployment identity receives `Container Apps Jobs Operator` scoped only to the migration job. After apply, copy each corresponding deployment identity client-ID output to that repository's GitHub Environment as `AZURE_CLIENT_ID`.

The Core and NLP images expose `/health` and `/ready` on port `8080`, so Terraform enables both liveness and database-readiness probes by default. Keep these probes enabled for future releases; a new revision must not receive traffic or remain active when its process or PostgreSQL dependency is unhealthy.

The Core and NLP APIs have external HTTPS ingress. Both are currently exposed without application authentication, so do not treat either endpoint as private.

The API URL outputs remain available with:

```powershell
terraform output -raw core_swagger_url
terraform output -raw nlp_swagger_url
```

The application images must serve Swagger at `/swagger/index.html`. Development deployments already set `ASPNETCORE_ENVIRONMENT=Development`; if an application restricts Swagger to Development, keep that restriction explicit in the application repository before exposing a production deployment.

Do not use application deployment identities for Terraform or at runtime. The Container Apps continue to use `id-olga-core-<environment>` and `id-olga-nlp-<environment>` for ACR pull and Key Vault access.

## Database deployment

PostgreSQL uses a private endpoint for Container Apps and the database migration job. Direct DBeaver administration is enabled only for the exact `/32` addresses declared per environment in `postgres-access.auto.tfvars`; there is no broad Azure-services firewall exception. Key Vault accepts the same `/32`; platform administrators receive Key Vault data-plane administration, while the PostgreSQL administrator retains explicit read access to the `postgresql-connection` secret. Use its `olga_migration_admin` credentials for unrestricted OLGA schema administration, including table and procedure DDL and DML. Microsoft Entra database authentication remains enabled for future identity-based access. Update the firewall entry and re-apply Terraform whenever the administrator's public IP changes.

The database delivery job reads the migration-administrator connection from the private Key Vault through its dedicated managed identity; GitHub never receives the database password. The one-time baseline can be deployed through that job or the guarded DBeaver entry script. Later manual database changes remain an operator responsibility and should be recorded as reviewed SQL in the database repository before they are executed in production.

Changing the already-created dev server from delegated-subnet networking to this private-endpoint/public-firewall model requires PostgreSQL replacement. Back up any required dev data and inspect the saved Terraform plan for the server replacement before approving apply. Production uses the same private-endpoint, exact-IP firewall, Entra administrator, and single-secret authorization model; replace the current administrator/IP values before creating prod if its approved operator or egress IP differs.

## Application readiness

- Core API expects port `8080`, `/health`, `/ready`, `ConnectionStrings__PostgreSql`, and `ServiceAuthorization__Token`.
- NLP API expects the same probes and secrets. It uses `EmbeddingProvider=Azure` and `EmbeddingProcessing__Mode=Queued`; evaluation endpoints retain direct managed-identity access to Azure OpenAI.
- The NLP worker remains at one replica for PostgreSQL polling and uses the same private Azure OpenAI endpoint with its own managed identity.
- API Management is not enabled by default; enable it after the OpenAPI import, OIDC validation, throttling, and policy configuration are defined.

## Mobile identity boundary

Microsoft Entra External ID owns Email OTP, Google federation, and mobile token issuance. The Google-only workflow associates the configured provider with the existing user flow through Microsoft Graph. Terraform does not store the Google client secret, OTPs, access tokens, refresh tokens, authorization codes, customer identities, or Microsoft Graph credentials.

### React Native / Expo authentication handoff

The mobile application continues to use the existing Microsoft Entra browser-delegated Authorization Code flow with PKCE. Google is presented by the same Entra-hosted page as Email OTP, so the mobile application must not add a Google SDK, Google client ID, or Google client secret. Both methods return through the same Entra callback and token exchange.

Install the Expo-compatible packages in the mobile repository:

```bash
npx expo install expo-auth-session expo-crypto expo-web-browser expo-secure-store
```

Add these non-secret development settings:

```dotenv
EXPO_PUBLIC_ENVIRONMENT=dev
EXPO_PUBLIC_ENTRA_CLIENT_ID=e8db01a0-3a93-48e0-86fa-68123e026088
EXPO_PUBLIC_ENTRA_TENANT_ID=d6b05a66-a3b7-442c-b56f-d4d7a9e154ba
EXPO_PUBLIC_ENTRA_AUTHORITY=https://olgaconnectdev.ciamlogin.com/
EXPO_PUBLIC_ENTRA_REDIRECT_URI=olga-dev://auth
EXPO_PUBLIC_OLGA_API_SCOPE=api://733db389-f55d-4a33-8cd6-18a14393e3d9/access_as_user
```

Register the callback scheme without replacing the mobile project's existing bundle and package identifiers:

```json
{
  "expo": {
    "scheme": "olga-dev",
    "plugins": ["expo-secure-store"]
  }
}
```

Configure `expo-auth-session` with issuer `https://olgaconnectdev.ciamlogin.com/d6b05a66-a3b7-442c-b56f-d4d7a9e154ba/v2.0`, redirect URI `olga-dev://auth`, PKCE, and scopes `openid`, `profile`, `email`, `offline_access`, and `api://733db389-f55d-4a33-8cd6-18a14393e3d9/access_as_user`. Open the system browser, exchange the returned authorization code with the PKCE verifier and no client secret, then store tokens only in `expo-secure-store`. Use an Expo development or standalone build for callback testing; Expo Go does not claim the registered `olga-dev` scheme.

The existing sign-up/sign-in button may remain unchanged: the Entra-hosted page now displays both Email OTP and Google. Never add `GOOGLE_CLIENT_SECRET` or any other client secret to the mobile source, Expo environment, build configuration, logs, analytics, AsyncStorage, Redux persistence, or SQLite. The complete hook, refresh, sign-out, error-handling, and test examples are in [docs/MOBILE_ENTRA_EXTERNAL_ID.md](docs/MOBILE_ENTRA_EXTERNAL_ID.md).

Core API, NLP API, Swagger, and health endpoints remain unauthenticated during the accepted temporary MVP phase. The mobile application can acquire and send an access token, but the APIs do not validate it yet. Do not interpret the identity outputs as API enforcement.

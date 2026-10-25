# OLGA Connect Azure infrastructure

Terraform project for isolated OLGA Connect development and production environments. GitHub uses `dev` and `prd`; Terraform retains its established internal values `dev` and `prod`.

GitHub Actions validation, planning, deployment, environment setup, and incident guidance are documented in [docs/TERRAFORM_CI_CD.md](docs/TERRAFORM_CI_CD.md). The Core worker, chat messaging, realtime, push, credential handoff, and configuration matrix are in [docs/CORE_CHAT_INFRASTRUCTURE.md](docs/CORE_CHAT_INFRASTRUCTURE.md). Microsoft Entra External ID Email OTP and Google setup is documented in [docs/ENTRA_EXTERNAL_ID.md](docs/ENTRA_EXTERNAL_ID.md), the independent Apple federation workflow is documented in [docs/APPLE_EXTERNAL_ID.md](docs/APPLE_EXTERNAL_ID.md), and the mobile integration steps are in [docs/MOBILE_ENTRA_EXTERNAL_ID.md](docs/MOBILE_ENTRA_EXTERNAL_ID.md), with the accepted temporary unauthenticated-API risk in [docs/SECURITY_DEBT.md](docs/SECURITY_DEBT.md).

## Provisioned baseline

- Resource group, mandatory tags, monthly budget alerts
- Log Analytics and Application Insights
- Azure Container Registry with managed-identity image pulls
- VNet-integrated Container Apps and private-endpoint subnets
- PostgreSQL 17 Flexible Server with private application connectivity, IP-restricted DBeaver access, Microsoft Entra administration, 7-day development backup, `vector`, and `pg_stat_statements`
- Private Key Vault and Blob Storage with purpose-specific containers
- Optional Service Bus Standard integration topic, filtered Core subscription, and consumed work queue with duplicate detection and dead-letter behavior
- Core and NLP APIs with external HTTPS ingress
- Always-on NLP PostgreSQL polling worker with managed-identity access to ACR, Key Vault, and Azure OpenAI
- Dedicated Core outbox/completion/content-scan worker with its own managed identity when Service Bus is enabled
- Standard chat services using Service Bus, SignalR, Notification Hubs, Content Safety, and Defender for Storage on-upload malware scanning; optional Azure OpenAI, API Management, and Static Web Apps

## Prerequisites

- Terraform 1.9 or later
- Azure CLI authenticated to the target tenant
- An approved Azure subscription and deployment region
- Contributor plus User Access Administrator permissions for the initial deployment
- Remote-state storage bootstrapped once

Terraform grants every principal listed for the active environment in `platform_administrator_principal_ids_by_environment` resource-group `Contributor` plus the data-plane roles required by the provisioned services: monitoring read, ACR push/delete, Key Vault administration, Blob data ownership, and—when enabled—Service Bus, Content Safety, Azure OpenAI, SignalR, and Notification Hubs administration. PostgreSQL data access remains controlled by `postgres_access_by_environment.entra_admin`. These assignments do not bypass private endpoints, service firewalls, or IP allowlists. The Terraform deployment identity needs `User Access Administrator` (or `Owner`) to create the assignments.

## First development deployment

For local deployment, create `olga-connect-dev.auto.tfvars` with the required non-secret values declared in `variables.tf`. Terraform loads this file automatically, and Git ignores it.

External tenant creation is included in `bootstrap/external-tenant`. The manual **External ID - Plan Initial Dev Tenant Creation** workflow performs a guarded plan; Microsoft requires the initial tenant creation apply to use a delegated user token, so that one-time apply runs locally. After the tenant exists, the protected **External ID - Configure Google Provider** workflow uses an environment-specific GitHub OIDC application to create or rotate the Google provider and associate it with the existing customer user flow through Microsoft Graph. It verifies that Email OTP remains associated and does not run Terraform or modify the existing applications, service principals, owners, attributes, or native-authentication settings. The Google secret is read only from the matching GitHub Environment secret and never enters Terraform. Production uses an independent tenant, OIDC identity, Google credential, and GitHub Environment configuration.

The separate protected **External ID - Configure Apple Provider** workflow creates or rotates only Apple and adds it to that environment's existing customer user flow. It records and verifies preservation of every current provider association, consumes the `.p8` key only from the matching GitHub Environment secret, and does not rerun or depend on Google. Dev and prd use independent Apple Service IDs and signing credentials; see [docs/APPLE_EXTERNAL_ID.md](docs/APPLE_EXTERNAL_ID.md).

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

The initial dev configuration uses a $50 monthly budget with alerts at 50%, 80%, and 100%; a December 1, 2026 review date; PostgreSQL `B_Standard_B1ms`; 32 GiB database storage; and 0.1 GB/day telemetry caps. Azure OpenAI, NLP application delivery, and the Free-tier admin Static Web App are enabled. The standard chat platform provisions Service Bus, SignalR, Notification Hubs, and Content Safety by default; API Management remains optional.

The first apply uses Microsoft's public Container Apps bootstrap image. Application repositories own subsequent immutable image revisions; Terraform owns identities, secrets, registry authentication, ingress, and ports. Core and NLP are independently configurable and both use port `8080` by default:

```hcl
core_application_delivery_enabled = true
core_health_probes_enabled         = true
core_api_min_replicas              = 0
nlp_application_delivery_enabled  = true
nlp_health_probes_enabled          = true
nlp_api_min_replicas               = 0
```

The infrastructure apply creates one deployment identity per repository and trusts only that repository's immutable subject for the matching GitHub Environment. Core and NLP receive `AcrPush`. The Core deployment identity receives `Container Apps Contributor` scoped only to the Core API, while the NLP deployment identity receives `Container Apps Contributor` scoped separately to both the NLP API and NLP worker. The database deployment identity receives `Container Apps Jobs Operator` scoped only to the migration job. After apply, copy each corresponding deployment identity client-ID output to that repository's GitHub Environment as `AZURE_CLIENT_ID`.

The Core and NLP images expose `/health` and `/ready` on port `8080`, so Terraform enables both liveness and database-readiness probes by default. Keep these probes enabled for future releases; a new revision must not receive traffic or remain active when its process or PostgreSQL dependency is unhealthy.

When API minimum replica values are omitted, Terraform defaults development to `0` for scale-to-zero and production to `2` for availability during replica failure or maintenance. In production, Core scales from 2 to 5 replicas at 50 concurrent requests per replica with 0.5 vCPU/1 GiB each; NLP scales from 2 to 5 at 25 concurrent requests per replica with 1 vCPU/2 GiB each. The production NLP worker remains two 1-vCPU/2-GiB replicas. Service Bus additionally creates a separate Core worker, defaulting to one development replica and two production replicas. Development APIs can cold-start; use `core_api_min_replicas=1` during realtime testing.

Production also uses a zone-redundant Container Apps environment, Premium zone-redundant ACR, ZRS Blob Storage, and PostgreSQL General Purpose compute with zone-redundant high availability, 128 GiB storage, automatic storage growth, and 35-day retention. Geo-redundant PostgreSQL backup is explicitly configurable and remains disabled in Malaysia West because Azure does not support it there; zone-redundant high availability and in-region backups remain enabled. Production telemetry retains 90 days, has a 5-GB daily cap with full sampling, and alerts the configured `BUDGET_ALERT_EMAILS` recipients for replica loss, container CPU/memory pressure, and PostgreSQL CPU/memory/storage pressure. Confirm SKU and availability-zone support in the selected Azure region during the reviewed production plan.

The Core and NLP APIs have external HTTPS ingress. Current development images remain unauthenticated. Production Core creation is gated by `core_authentication_enforced=true`, which may be set only for an image that actually validates External ID tokens and disables `X-Member-Id`/default-member identity selection.

The API URL outputs use each Container App's stable ingress hostname rather than a revision-specific hostname, so application releases do not change the published URL. They remain available with:

```powershell
terraform output -raw core_swagger_url
terraform output -raw nlp_swagger_url
```

## Admin portal deployment

The admin portal is a React/Vite client-side SPA, so Azure Static Web Apps hosts it without a long-running App Service plan or a container image. The Static Web Apps region is configured separately from the primary workload region; development uses `eastasia` and the Free plan. The production example uses the Standard plan so an SLA and network restrictions can be adopted without changing hosting technology.

After the infrastructure apply, retrieve the site values:

```powershell
terraform output -raw admin_static_web_app_name
terraform output -raw admin_static_web_app_url
```

Use the URL as the Microsoft Entra SPA redirect origin and the allowed CORS origin in Olga.Core. In the admin portal repository's matching GitHub Environment, set `ADMIN_API_BASE_URL`, the `ADMIN_AUTH_*` variables, and `AZURE_STATIC_WEB_APPS_API_TOKEN`. Retrieve the deployment token from the Static Web App in Azure Portal; do not store it in Terraform variables, outputs, or source control. The portal's existing deployment workflow builds once, writes the environment-specific `config.json` and security policy, and uploads `dist` to this resource.

Do not treat the portal's client-side MSAL role check as authorization. Before production use, Olga.Core must validate the access token and require the `Olga.Admin` application role on every `/v1/admin` route. The current Core API intentionally leaves those routes open, so deploying the static files does not make the administrative operations secure.

The application images must serve Swagger at `/swagger/index.html`. Development deployments already set `ASPNETCORE_ENVIRONMENT=Development`; if an application restricts Swagger to Development, keep that restriction explicit in the application repository before exposing a production deployment.

Do not use application deployment identities for Terraform or at runtime. The Container Apps continue to use `id-olga-core-<environment>` and `id-olga-nlp-<environment>` for ACR pull and Key Vault access.

## Database deployment

PostgreSQL uses a private endpoint for Container Apps and the database migration job. Direct DBeaver administration is enabled only for the exact `/32` addresses declared per environment in `postgres-access.auto.tfvars`; there is no broad Azure-services firewall exception. Key Vault accepts the same `/32`; platform administrators receive Key Vault data-plane administration, while the PostgreSQL administrator retains explicit read access to the `postgresql-connection` secret. Use its `olga_migration_admin` credentials for unrestricted OLGA schema administration, including table and procedure DDL and DML. Microsoft Entra database authentication remains enabled for future identity-based access. Update the firewall entry and re-apply Terraform whenever the administrator's public IP changes.

The database delivery job reads the migration-administrator connection from the private Key Vault through its dedicated managed identity; GitHub never receives the database password. The one-time generated baseline creates schema v2.4 and can be deployed through that job or the guarded DBeaver entry script. Apply the database repository's v2.5 profile-image and v2.6 Core outbox-leasing migrations in order before deploying the current Core image. Later manual database changes remain an operator responsibility and should be recorded as reviewed SQL in the database repository before they are executed in production.

Changing the already-created dev server from delegated-subnet networking to this private-endpoint/public-firewall model requires PostgreSQL replacement. Back up any required dev data and inspect the saved Terraform plan for the server replacement before approving apply. Production uses the same private-endpoint, exact-IP firewall, Entra administrator, and single-secret authorization model; replace the current administrator/IP values before creating prod if its approved operator or egress IP differs.

## Application readiness

- Core API expects port `8080`, `/health`, `/ready`, `ConnectionStrings__PostgreSql`, and `ServiceAuthorization__Token`.
- Core worker expects the exact Service Bus and Blob settings documented in `docs/CORE_CHAT_INFRASTRUCTURE.md`; it is a separate Container App and identity from the NLP worker.
- NLP API expects the same probes and secrets. It uses `EmbeddingProvider=Azure` and `EmbeddingProcessing__Mode=Queued`; evaluation endpoints retain direct managed-identity access to Azure OpenAI.
- NLP API and worker use `AzureOpenAI__ModelVersion` for the stable application model identifier stored in `nlp.nlp_model_version`. This is distinct from `azure_openai_model_version`, which selects the Azure model catalog version.
- The NLP worker remains at one replica for PostgreSQL polling and uses the same private Azure OpenAI endpoint with its own managed identity.
- API Management is not enabled by default; enable it after the OpenAPI import, OIDC validation, throttling, and policy configuration are defined.

## Mobile identity boundary

Microsoft Entra External ID owns Email OTP, Google and Apple federation, and mobile token issuance. Independent provider workflows associate Google and Apple with the existing user flow through Microsoft Graph. Terraform does not store the Google client secret, Apple private key, OTPs, access tokens, refresh tokens, authorization codes, customer identities, or Microsoft Graph credentials.

### React Native / Expo authentication handoff

The mobile application uses Microsoft Entra's browser-delegated Authorization Code flow with PKCE for Email OTP, Google, and Apple. A generic action opens the hosted chooser; optional provider-specific actions use `domain_hint=google` or `domain_hint=apple` against the same Entra authorization endpoint. All methods return through the same registered callback and token exchange. Do not add direct Google or Apple SDKs.

The mobile build needs only the environment's non-secret Entra client ID, tenant ID, authority, redirect URI, and API scope. It must never contain the Google secret, Apple Service ID, Apple provider object ID, Team ID, Key ID, `.p8` key, OTPs, authorization codes, or tokens. Use an Expo development or standalone build for callback testing because Expo Go cannot claim the required custom scheme.

The complete runtime values, Expo configuration, `useEntraLogin` hook, provider routing contract, refresh/sign-out behavior, and physical-device verification checklist are maintained in [docs/MOBILE_ENTRA_EXTERNAL_ID.md](docs/MOBILE_ENTRA_EXTERNAL_ID.md).

The current Core API, NLP API, Swagger, and health endpoints remain unauthenticated during the accepted development-only MVP phase. The mobile application can acquire and send an access token, but the current APIs do not validate it yet. Do not interpret the identity outputs or `core_authentication_enforced` flag as API enforcement; production requires a compatible Core image first.

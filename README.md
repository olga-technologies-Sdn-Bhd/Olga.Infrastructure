# OLGA Connect Azure infrastructure

Terraform project for isolated OLGA Connect development, test, and production environments.

GitHub Actions validation, planning, deployment, environment setup, and incident guidance are documented in [docs/TERRAFORM_CI_CD.md](docs/TERRAFORM_CI_CD.md).

## Provisioned baseline

- Resource group, mandatory tags, monthly budget alerts
- Log Analytics and Application Insights
- Azure Container Registry with managed-identity image pulls
- VNet-integrated Container Apps and private-endpoint subnets
- PostgreSQL 17 Flexible Server with private application connectivity, IP-restricted DBeaver access, Microsoft Entra administration, 7-day development backup, `vector`, and `pg_stat_statements`
- Private Key Vault and Blob Storage with purpose-specific containers
- Optional Service Bus Standard queues with duplicate detection and dead-letter behavior
- Core and NLP APIs with external HTTPS ingress for browser-based Swagger access
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

```powershell
.\scripts\bootstrap-state.ps1 `
  -SubscriptionId 'e0bb013f-a8af-4d60-9c5b-0140b361f257' `
  -Location 'malaysiawest' `
  -StorageAccountName '<globally-unique-state-account>' > backend.hcl

# Create olga-connect-dev.auto.tfvars and fill its required non-secret values.

terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=dev.tfplan
terraform apply dev.tfplan
```

The initial dev configuration uses a $50 monthly budget with alerts at 50%, 80%, and 100%; a December 1, 2026 review date; PostgreSQL `B_Standard_B1ms`; 32 GiB database storage; Container Apps scaling from zero to one replica; and 0.1 GB/day telemetry caps. Service Bus, API Management, Static Web Apps, Azure OpenAI, Content Safety, SignalR, and Notification Hubs remain disabled.

The first apply uses Microsoft's public Container Apps bootstrap image. Application repositories own subsequent immutable image revisions; Terraform owns identities, secrets, registry authentication, ingress, and ports. Core and NLP are independently configurable and both use port `8080` by default:

```hcl
core_application_delivery_enabled = true
core_health_probes_enabled         = true
nlp_application_delivery_enabled  = true
nlp_health_probes_enabled          = true
```

The infrastructure apply creates one deployment identity per repository and trusts only that repository's immutable subject for the matching GitHub Environment. Core and NLP receive `AcrPush` plus `Container Apps Contributor` on their own app. The database deployment identity receives `AcrPush` plus `Container Apps Jobs Operator` on the migration job. After apply, copy each corresponding deployment identity client-ID output to that repository's GitHub Environment as `AZURE_CLIENT_ID`.

The Core and NLP images expose `/health` and `/ready` on port `8080`, so Terraform enables both liveness and database-readiness probes by default. Keep these probes enabled for future releases; a new revision must not receive traffic or remain active when its process or PostgreSQL dependency is unhealthy.

Both Container Apps have external HTTPS ingress. After applying Terraform, retrieve the browser-ready Swagger UI addresses with:

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
- NLP API expects the same probes and secrets. Development sets `EmbeddingProvider=Fake` and `EmbeddingProcessing__Mode=Inline`.
- Enable Azure OpenAI only after the NLP adapter is implemented and regional model quota is approved.
- API Management is not enabled by default; enable it after the OpenAPI import, OIDC validation, throttling, and policy configuration are defined.

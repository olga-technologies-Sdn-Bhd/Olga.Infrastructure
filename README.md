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

## First development deployment

The checked-in `olga-connect-dev.example.tfvars` file is configured for the `olga-connect-dev` subscription in tenant `9972baa6-9591-43d7-8b13-59da8e6f1a72`. Terraform does not load this example file automatically. For local deployment, copy it to `olga-connect-dev.auto.tfvars`, which Terraform loads automatically and Git ignores.

```powershell
.\scripts\bootstrap-state.ps1 `
  -SubscriptionId 'e0bb013f-a8af-4d60-9c5b-0140b361f257' `
  -Location 'malaysiawest' `
  -StorageAccountName '<globally-unique-state-account>' > backend.hcl

Copy-Item .\olga-connect-dev.example.tfvars .\olga-connect-dev.auto.tfvars
# Fill non-secret environment values in olga-connect-dev.auto.tfvars.

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

PostgreSQL uses a private endpoint for Container Apps and the database migration job. Direct DBeaver administration is enabled only for the exact `/32` addresses declared per environment in `postgres-access.auto.tfvars`; there is no broad Azure-services firewall exception. Key Vault accepts the same `/32`, and the declared Entra administrator receives read access only to `postgresql-migration-connection`. The migration managed identity is the only workload identity that can read that secret. Use its `olga_migration_admin` credentials for unrestricted OLGA schema administration, including table and procedure DDL and DML.

Core API, NLP API, and applicable workers read the separate `postgresql-dml-connection` secret and connect only as `olga_dml_user`. They cannot read the migration connection. The database delivery job reads the migration-administrator connection plus bootstrap-only DML username/password secrets through its dedicated managed identity; GitHub never receives either database password. Development and production have separate Terraform state, PostgreSQL servers, generated passwords, Key Vaults, secrets, and managed identities.

Azure RBAC and PostgreSQL roles are separate authorization systems. Key Vault RBAC controls who can retrieve connection material; database roles control what a login can do after connecting. Azure Database for PostgreSQL Flexible Server does not expose literal PostgreSQL `SUPERUSER`. Within that limitation, `olga_migration_admin` is the Flexible Server administrator and receives `olga_ddl_admin`, `olga_dml_writer`, and `olga_reader` with membership administration rights. The database migration repository must implement the ownership and idempotent login provisioning contract in [PostgreSQL identity model](docs/postgresql-identity-model.md).

Changing the already-created dev server from delegated-subnet networking to this private-endpoint/public-firewall model requires PostgreSQL replacement. Back up any required dev data and inspect the saved Terraform plan for the server replacement before approving apply. Production uses the same private-endpoint, exact-IP firewall, Entra administrator, and secret-scoped authorization model; replace the current administrator/IP values before creating prod if its approved operator or egress IP differs.

## Application readiness

- Core API expects port `8080`, `/health`, `/ready`, and receives `postgresql-dml-connection` as `ConnectionStrings__PostgreSql`.
- NLP API receives the same DML connection as `ConnectionStrings__PostgreSql`. Development sets `EmbeddingProvider=Fake` and `EmbeddingProcessing__Mode=Inline`.
- A future worker deployment must use its existing managed identity to reference `postgresql-dml-connection`; Terraform already grants that identity read access to only the DML connection and other explicitly scoped runtime secrets.
- Enable Azure OpenAI only after the NLP adapter is implemented and regional model quota is approved.
- API Management is not enabled by default; enable it after the OpenAPI import, OIDC validation, throttling, and policy configuration are defined.

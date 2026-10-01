# Infrastructure decisions

- Terraform is the sole owner of Azure resources in this environment; Portal edits must be reconciled into code.
- Each environment uses an isolated resource group, state key, PostgreSQL server, identities, and secrets.
- PostgreSQL, Blob Storage, and Key Vault use private networking; runtime services enter through the Container Apps VNet.
- GitHub Actions authenticates with OIDC. Stored Azure client secrets are prohibited.
- Database schema deployment is a separate gated operation; API startup never performs DDL.
- Development uses fake inline embeddings until the Azure provider adapter, approved region, and quota are ready.
- API Management, Azure OpenAI, and the admin site are feature-gated because their product inputs are not final.
- The initial database password enables schema bootstrap. Replace runtime database password use with Entra workload authentication before production.
- Exactly two deployment environments are supported externally: `dev` and `prd`. The established Terraform values remain `dev` and `prod`; CI maps `prd` to `prod`, and unsupported values fail validation.
- External tenant creation is isolated in `bootstrap/external-tenant` and uses the existing AzAPI provider with separate state. `bootstrap/external-directory` creates the Email OTP user-flow and application baseline. Independent Microsoft Graph workflows create or rotate Google and Apple and associate them with that existing flow, so provider credentials never enter Terraform state; later directory plans retain the associations by using only the non-secret provider object IDs.
- Entra External ID Email OTP, Google, and Apple protect the mobile login experience only. Core and NLP remain unauthenticated under the accepted temporary risk recorded in `docs/SECURITY_DEBT.md`.


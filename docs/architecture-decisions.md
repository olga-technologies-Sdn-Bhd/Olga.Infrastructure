# Infrastructure decisions

- Terraform is the sole owner of Azure resources in this environment; Portal edits must be reconciled into code.
- Each environment uses an isolated resource group, state key, PostgreSQL server, identities, and secrets.
- PostgreSQL, Blob Storage, and Key Vault use private networking; runtime services enter through the Container Apps VNet.
- GitHub Actions authenticates with OIDC. Stored Azure client secrets are prohibited.
- Database schema deployment is a separate gated operation; API startup never performs DDL.
- Development uses fake inline embeddings until the Azure provider adapter, approved region, and quota are ready.
- API Management, Azure OpenAI, and the admin site are feature-gated because their product inputs are not final.
- The initial database password enables schema bootstrap. Replace runtime database password use with Entra workload authentication before test or production.


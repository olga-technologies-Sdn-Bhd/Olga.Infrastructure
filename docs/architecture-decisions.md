# Infrastructure decisions

- Terraform is the sole owner of Azure resources in this environment; Portal edits must be reconciled into code.
- Each environment uses an isolated resource group, state key, PostgreSQL server, identities, and secrets.
- PostgreSQL, Blob Storage, and Key Vault use private networking; runtime services enter through the Container Apps VNet.
- GitHub Actions authenticates with OIDC. Stored Azure client secrets are prohibited.
- Database schema deployment is a separate gated operation; API startup never performs DDL.
- `olga_migration_admin` remains the Azure PostgreSQL server administrator. Azure does not expose PostgreSQL `SUPERUSER`, so complete OLGA control is provided through object ownership and the `olga_ddl_admin`, `olga_dml_writer`, and `olga_reader` roles with `ADMIN OPTION`.
- Runtime services connect only as `olga_dml_user`, which receives `olga_dml_writer` and no DDL, role-administration, Azure-administrator, replication, bypass-RLS, or database-creation privileges.
- Migration and runtime connection strings are separate Key Vault secrets with secret-scoped Azure RBAC. Azure RBAC grants secret retrieval; PostgreSQL roles independently grant database permissions.
- Every environment has its own Terraform state, server, Key Vault, generated administrator and DML passwords, secrets, and managed identities. Credentials and resources are never shared between development and production.
- Development uses fake inline embeddings until the Azure provider adapter, approved region, and quota are ready.
- API Management, Azure OpenAI, and the admin site are feature-gated because their product inputs are not final.
- Password authentication is retained for the migration and DML logins; passwords are generated per environment, stored only in Terraform state and Key Vault, and never exposed through ordinary outputs or application settings.

# Infrastructure decisions

- Terraform is the sole owner of Azure resources in this environment; Portal edits must be reconciled into code.
- Each environment uses an isolated resource group, state key, PostgreSQL server, identities, and secrets.
- PostgreSQL, Blob Storage, and Key Vault use private networking; runtime services enter through the Container Apps VNet.
- GitHub Actions authenticates with OIDC. Stored Azure client secrets are prohibited.
- Database schema deployment is a separate gated operation; API startup never performs DDL.
- Development and production examples provision private Azure OpenAI and configure queued NLP
  processing with `text-embedding-3-small`; fake inline embeddings are local-development behavior,
  not the deployed baseline.
- API Management remains feature-gated. Azure OpenAI and the admin site remain configurable, but
  the reviewed development and production examples enable them.
- The initial database password enables schema bootstrap. Replace runtime database password use with Entra workload authentication before production.
- Exactly two deployment environments are supported externally: `dev` and `prd`. The established Terraform values remain `dev` and `prod`; CI maps `prd` to `prod`, and unsupported values fail validation.
- External tenant creation is isolated in `bootstrap/external-tenant` and uses the existing AzAPI provider with separate state. `bootstrap/external-directory` creates the Email OTP user-flow and application baseline. Independent Microsoft Graph workflows create or rotate Google and Apple and associate them with that existing flow, so provider credentials never enter Terraform state; later directory plans retain the associations by using only the non-secret provider object IDs.
- Core outbox and completion processing runs in a dedicated Core worker Container App and user-assigned identity. The existing NLP worker remains a separate PostgreSQL-polling workload.
- Service Bus contains only entities with a current consumer: `integration-events`, the filtered `core-nlp-completions` subscription, and `content-scan`. RBAC is entity-scoped; Core API and NLP identities do not receive namespace-wide messaging roles.
- Service Bus, SignalR, Notification Hubs, and Content Safety remain explicit cost-bearing feature
  flags; the reviewed development and production examples enable all four for the standard chat
  baseline. SignalR and Service Bus remain in Malaysia West; because Notification Hubs and Content
  Safety are unavailable there, only those two services use Southeast Asia. External provider
  credentials remain outside Terraform state.
- Notification Hubs data-plane access uses a dedicated send-only SAS authorization rule because
  the service does not support managed-identity data-plane roles. Terraform stores its connection
  string as sensitive remote state and in the private Key Vault. The URI is prepared for the later
  Core integration without changing the current Core API or worker configuration.
- Notification Hubs has no diagnostic setting targeting Log Analytics because its metric export is
  disabled and its operational logs do not support that destination. Azure Activity Log and direct
  platform-metric alerts provide the supported monitoring baseline.
- Entra External ID Email OTP, Google, and Apple protect the mobile login experience only in the current Core build. Infrastructure supplies the API validation contract and blocks production unless an operator attests that the selected image enforces it; see `docs/SECURITY_DEBT.md`.


# Terraform CI/CD

The repository uses one OLGA-style workflow, `.github/workflows/terraform-validate-plan-apply.yml`, for validation, speculative planning, and deployment. Every push or manual deployment creates a new saved plan and applies only that plan. Pull-request plans are never applied or reused after merge.

## Branch and environment mapping

| Event | Branch/input | GitHub target | Terraform `environment` | Action |
| --- | --- | --- | --- | --- |
| Pull request | `develop` | `dev` | `dev` | Validate, lint, scan, speculative plan |
| Push/merge | `develop` | `dev` | `dev` | Validate, create new plan, apply exact plan |
| Pull request | `main` | `prd` | `prod` | Validate, lint, scan, speculative plan |
| Push/merge | `main` | `prd` | `prod` | Validate, create new plan, approve, apply exact plan |
| Manual | `dev` or `prd` | selected | `dev` or `prod` | Same gates and a fresh plan |

The external name is `prd`, while the existing Terraform contract uses `prod`. This preserves current OLGA resource names and production controls such as Key Vault purge protection.

Fork pull requests receive no Azure token. They run formatting, initialization without a backend, validation, TFLint, and Trivy; a maintainer must reproduce their cloud plan from a trusted branch.

## GitHub Environments

Create four GitHub Environments:

- `dev-plan` and `prd-plan`: read-only Azure planning identities plus remote-state access.
- `dev`: dev apply identity. Restrict deployment branches to `develop`.
- `prd`: production apply identity. Restrict to `main`, require reviewers, and prevent self-review.

Separate plan environments allow the production plan and destructive-action count to exist before the protected `prd` approval is requested.

Configure these environment-scoped variables in every matching plan/apply environment:

| Variable | Purpose |
| --- | --- |
| `AZURE_CLIENT_ID` | Client ID of the environment's managed identity or Entra application |
| `AZURE_TENANT_ID` | Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target subscription |
| `TFSTATE_RESOURCE_GROUP` | Existing state resource group, typically `rg-olga-tfstate` |
| `TFSTATE_STORAGE_ACCOUNT` | Existing state storage account |
| `TFSTATE_CONTAINER` | State container, typically `tfstate` |
| `TFSTATE_KEY` | `olga/dev.tfstate` or `olga/prd.tfstate` |
| `AZURE_LOCATION` | Azure deployment region, such as `malaysiawest` |
| `OWNER` | Resource owner tag, such as `olga-platform` |
| `COST_CENTER` | Cost allocation tag, such as `olga-connect` |
| `EXPIRY_DATE` | Review/expiry date in `YYYY-MM-DD` format |
| `BUDGET_AMOUNT_USD` | Monthly Azure budget amount, `50` for dev |
| `BUDGET_ALERT_EMAILS` | Terraform list value, for example `["sreedharan@ol-ga.com"]` |

The plan workflow maps these GitHub Environment variables to Terraform `TF_VAR_*` inputs. Add future non-secret Terraform inputs the same way. Never store client secrets, storage keys, passwords, state, saved plans, or sensitive tfvars as GitHub variables.

## Azure OIDC federation

For each identity, create a GitHub Actions federated identity credential with issuer `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`, and one exact subject (replace `ORG/REPOSITORY`):

```text
repo:ORG/REPOSITORY:environment:dev-plan
repo:ORG/REPOSITORY:environment:dev
repo:ORG/REPOSITORY:environment:prd-plan
repo:ORG/REPOSITORY:environment:prd
```

Do not add secrets or broad repository/pull-request federated subjects to apply identities. GitHub Environment deployment-branch rules are part of this trust boundary.

Application delivery uses separate identities managed by this Terraform project:

- Core identity: `id-gh-olga-core-<environment>-deploy`
- Core dev subject: `repo:Ol-gaTechnologies@306667340/Olga.Core@1358930841:environment:dev`
- NLP identity: `id-gh-olga-nlp-<environment>-deploy`
- NLP dev subject: `repo:Ol-gaTechnologies@306667340/olga-nlp-api@1356082344:environment:dev`
- Database identity: `id-gh-olga-database-<environment>-deploy`
- Database dev subject: `repo:Ol-gaTechnologies@306667340/olga-database@1356201535:environment:dev`
- Registry permission: each identity has `AcrPush` scoped to the environment ACR
- API deployment permission: each API identity has `Container Apps Contributor` scoped only to its own Container App
- Database deployment permission: `Container Apps Jobs Operator` scoped only to the migration job

After Terraform creates the identities, copy `core_deployment_identity_client_id`, `nlp_deployment_identity_client_id`, and `database_deployment_identity_client_id` to the matching repository GitHub Environment as `AZURE_CLIENT_ID`. Keep tenant, subscription, ACR login server, resource group, Container App, and migration-job settings aligned with the infrastructure outputs. Each application workflow owns image digest releases and supplies its revision suffix. The database workflow starts an exact image digest as a one-off job execution. Terraform intentionally ignores API image drift while continuing to manage all other Container App configuration; Azure generates a fresh suffix for any Terraform-driven template revision.

Both Container Apps have liveness probes on `/health` and readiness probes on `/ready`, using port `8080`. The readiness endpoint verifies PostgreSQL connectivity. Keep these probes enabled in every environment after the real application images are deployed; bootstrap-only environments may temporarily disable them until application delivery is complete.

## Minimum Azure RBAC

Plan identities need `Reader` over only the target scope and `Storage Blob Data Contributor` on the single state container. The latter permits Azure Blob lease acquisition for Terraform state locking.

Apply identities need `Storage Blob Data Contributor` on the matching state container and permissions for the resources declared here. The current root module creates the resource group and its budget, so initial deployment requires subscription-scoped create permissions. Prefer a custom role limited to this repository's resource types; otherwise use `Contributor` during bootstrap and reduce scope after the resource group is pre-created or ownership is restructured.

The modules create ACR pull role assignments. Prefer `Role Based Access Control Administrator` with Azure ABAC conditions limiting allowed roles, principals, and scopes. `User Access Administrator` is a broader fallback. Never assign `Owner`, and keep dev and production identities separate.

## State, plans, and concurrency

The Azure Storage backend uses Entra authentication and distinct state keys:

```text
dev: olga/dev.tfstate
prd: olga/prd.tfstate
```

The `azurerm` backend uses Azure Blob leases for locking. Plans wait five minutes for a lock and applies wait ten minutes. Job concurrency allows only one apply per environment. Superseded dev plans are cancelled; production plans and active applies are never cancelled.

Saved-plan artifacts include the binary plan, a SHA-256 checksum, provenance metadata, and a value-free Markdown summary. Apply verifies the commit, environment, Terraform version, state key, and checksum. Artifacts expire after two days. Treat binary plan artifacts as sensitive because Terraform plans can contain state values; do not copy them to tickets or chat.

Plan/apply command output is suppressed to avoid leaking sensitive values. The job summary contains only environment, commit, and action counts.

## Destructive changes and production approval

The workflow counts every resource action containing `delete`, including replacements, and highlights the count in the job summary. Dev changes apply automatically after a successful plan, so review destructive changes during pull-request planning before merging to `develop`.

Production always waits at the protected `prd` Environment after planning. Reviewers must inspect the job summary and saved plan before approval, especially when deletion is reported. Reject unexpected destruction and correct the code; never reuse an older plan.

## Branch protection recommendations

Protect `develop` and `main` with pull requests, current branches, resolved conversations, and required `Validate, lint, and scan` plus plan checks. Block force-pushes/deletions and restrict direct pushes and workflow changes. Protect `.github/workflows/**`, `.tflint.hcl`, `.terraform.lock.hcl`, backend configuration, and Terraform modules with CODEOWNERS. Require platform/security review for `main` and disallow bypass.

The workflow intentionally has no path filters. GitHub can leave path-filtered required checks pending, and infrastructure policy should run on every pull request to these branches.

## Rollback and incidents

1. Hold new deployments. Do not cancel a running production apply unless incident command determines continuing is more dangerous.
2. Record the run URL, commit, redacted summary, Azure Activity Log evidence, and current state-blob version. Never post state or plan binaries in incident channels.
3. Establish whether apply completed or partially completed. Use a secure operator host for any refresh-only reconciliation.
4. Revert or correct source through review, then generate and approve a new plan. Never apply an old artifact as rollback.
5. If state is damaged, back it up and use Blob versioning/soft-delete recovery under two-person control. Never force-unlock until no process owns the lease.
6. Restore data-bearing services such as PostgreSQL through their backup runbooks; Terraform rollback does not restore deleted data.

## Private-network runners

GitHub-hosted Ubuntu runners are appropriate while the state data plane and required Azure control-plane endpoints are reachable. If the state account is private-endpoint-only or firewall-restricted, use an ephemeral hardened self-hosted runner with VNet routing and private DNS. A self-hosted runner is also required for operations that connect directly to private PostgreSQL, Key Vault, Storage, or other private service endpoints.

## Maintenance

Terraform, TFLint, the Azure TFLint plugin, and Trivy are pinned; downloaded scanner binaries are checksum-verified. GitHub Actions are pinned to immutable commit SHAs, and Dependabot checks them weekly. Promote upgrades through dev before production.

The budget start date is selected as the first day of the creation month and then ignored for drift because Azure treats it as immutable. A routine plan must not replace a budget merely because Terraform was run again. Budget replacement is expected only when an operator intentionally changes a replacement-only budget property.

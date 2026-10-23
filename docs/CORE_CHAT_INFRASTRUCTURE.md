# Core chat infrastructure

This document is the deployment contract for the OL-GA MVP Core API and the dedicated `Olga.Core.Worker`. The existing NLP API and NLP PostgreSQL polling worker remain separate resources and identities.

## Runtime flow

1. Core API writes business changes and `ops.outbox_event` in one PostgreSQL transaction.
2. The Core worker polls the outbox and sends each event to the `integration-events` topic with `MessageId=outbox_event_id`, enabling Service Bus duplicate suppression.
3. `core-nlp-completions` receives only `event_type = 'NlpMatchRequestCompleted.v1'` and the Core worker applies the completion to Core projections. Terraform updates the Azure-created `$Default` subscription rule in place so first deployment does not require a state import.
4. `ProfileImageUploaded.v1` is sent to `content-scan`; the Core worker validates and transforms the private pending blob. This is image validation, not a complete malware/content-safety pipeline.
5. The standard deployment provisions SignalR, Notification Hubs, and Content Safety. SignalR coordinates are injected into the Core API and Core worker: the API authenticates connections and the worker publishes committed outbox events. Provider credentials are never Terraform inputs or outputs.

Terraform intentionally does not create `embedding`, `notification`, `privacy-retention`, or `outbox` queues: no current Core or NLP process consumes them. Add an entity and entity-scoped RBAC only when the consuming code and deployment setting exist.

The current NLP worker writes `NlpMatchRequestCompleted.v1` to the NLP database outbox but does not yet contain a Service Bus publisher. Consequently, the filtered subscription is correctly provisioned but will not receive NLP completion messages until the NLP application adds a publisher using `MessageId=outbox_event_id`. Grant that publisher identity sender access only to `integration-events` when the code exists; do not broaden NLP access in advance.

The current Core source also has no SignalR hub integration and no Notification Hubs sender. The feature flags provision secure service boundaries and deployment settings, but enabling them does not create realtime or push behavior. Add the application integrations before enabling either service in a live environment; no unused notification queue is provisioned.

## Dependency and configuration matrix

| Workload setting/output | Supplied by | Purpose |
| --- | --- | --- |
| `ConnectionStrings__PostgreSql` | Key Vault `postgresql-connection` reference | API/worker database access without exposing the value in tfvars or outputs |
| `IdentityProtection__MasterKeyBase64` | Key Vault `identity-protection-master-key` reference | Core API ciphertext protection |
| `Storage__BlobServiceEndpoint` / `storage_blob_endpoint` | private Storage account endpoint | Private profile-image access; `chat-files` remains private and unused |
| `Storage__ManagedIdentityClientId` | Core API or Core worker user-assigned identity | Keyless Blob authentication |
| `Storage__PendingProfileImagesContainerName` | literal `profile-images-pending` | Reconciles the application default/name mismatch |
| `ServiceBus__FullyQualifiedNamespace` / `servicebus_fully_qualified_namespace` | Service Bus namespace | Managed-identity Service Bus client |
| `ServiceBus__ManagedIdentityClientId` | dedicated Core worker identity | Keyless Service Bus authentication |
| `ServiceBus__IntegrationTopicName` | `integration-events` topic | Transactional outbox publication |
| `ServiceBus__NlpCompletionSubscriptionName` | filtered `core-nlp-completions` subscription | NLP completion consumption |
| `ServiceBus__ContentScanQueueName` | `content-scan` queue | Profile-image work |
| `AzureAd__Instance` / `Authority` | External ID environment input | Token authority |
| `AzureAd__TenantId`, `ClientId`, `Audience`, `Issuer` | External ID environment input | Exact token validation boundary |
| `AzureAd__RequiredScope` | literal `access_as_user` | Delegated API permission |
| `AzureAd__RequiredRoles` | `external_identity_required_roles` | Optional application roles after directory roles exist |
| `Authentication__RequireAuthenticatedUsers` | `core_authentication_enforced` | Production deployment gate and application enforcement signal |
| `SignalR__Endpoint` / `signalr_endpoint` | SignalR resource | Managed realtime endpoint supplied to the Core API and Core worker; no connection string is emitted |
| `SignalR__ManagedIdentityClientId` | Core API or Core worker user-assigned identity | Keyless SignalR authentication for connection handling and committed-event publication |
| `NotificationHubs__NamespaceName`, `HubName` | optional Notification Hubs resources | Push routing coordinates |
| `core_worker_container_app_name` | dedicated Core worker Container App | Core image deployment target |
| `core_worker_identity_client_id` | dedicated Core worker identity | Core worker Azure SDK client ID |

The Core deployment identity has `Container Apps Contributor` only on the Core API and Core worker. The Core API and Core worker each receive `SignalR App Server` only when SignalR is enabled; the worker publishes committed chat events while the API owns authenticated connection handling. New Core worker Blob access is container-scoped. Existing storage-account Blob assignments for Core, NLP, and the NLP worker are preserved to avoid a disruptive permission migration and are recorded as security debt. Other new runtime roles are scoped to the resources or messaging entities used by their code. The NLP worker and its existing deployment path are otherwise unchanged.

## Availability and scaling

- Development Core API remains scale-to-zero by default. The first request after idle may wait for Container Apps cold start plus application/database initialization.
- When Service Bus is enabled, the Core worker defaults to one development replica so PostgreSQL outbox polling continues. Setting it to zero is allowed only in development and intentionally pauses outbox, completion, and scan processing until a replica is started.
- Production requires at least two Core API replicas, two Core worker replicas, and Service Bus. The worker uses process health as its liveness signal: an unhandled startup/runtime failure exits the process and Container Apps restarts it. The current worker exposes no HTTP health endpoint.
- Production alerts cover API/worker replica loss, Service Bus backlog and dead letters, SignalR system errors/server connections, Notification Hubs failures/invalid tokens, and PostgreSQL CPU/memory/storage pressure.
- A database-outbox age/count alert requires the Core worker to emit an Application Insights metric. Azure Monitor cannot query an application table with a native resource metric; add that metric in Core before claiming outbox-backlog monitoring is complete.

## Authentication release gate

Production plans fail unless `core_authentication_enforced=true`. Set it only when the selected Core image validates signature, issuer, audience, lifetime, `access_as_user`, and required roles; derives member identity from immutable token claims; and rejects both `X-Member-Id` identity selection and default-member fallback. The infrastructure injects the exact non-secret values but cannot make an application that ignores them secure. The current Core source still uses the insecure MVP selector, so it is not eligible for a production release.

## MVP infrastructure coverage

The infrastructure boundary for the non-Phase-2 chat backlog is covered as follows. This table describes platform readiness, not end-to-end feature completion; database, Core API, worker, and mobile behavior still have to implement their contracts.

| Requirement | Infrastructure coverage |
| --- | --- |
| CHAT-01 one-to-one text chat | Core API availability, dedicated Core worker, transactional-outbox transport, and optional managed SignalR are available. |
| CHAT-02 sent/delivered/read status | SignalR is available for low-latency receipt events; PostgreSQL remains the durable source of truth. |
| CHAT-03 connection lifecycle | The always-running production Core worker can execute expiry/lifecycle work. State transitions and scheduling belong to Core and PostgreSQL; no separate Azure queue is provisioned without a consumer. |
| CHAT-04 push notifications | Optional Notification Hubs, worker sender identity, protected APNS/FCM setup, diagnostics, and alerts are available. |
| CHAT-05 block and disconnect | External ID configuration and the production authentication gate protect the server boundary. Disconnect/block enforcement and the Bluetooth kill switch are application responsibilities and require no additional Azure resource. |
| CHAT-06 message deletion | The Core worker can execute asynchronous deletion/retention work. Policy and per-member deletion semantics belong to Core and PostgreSQL. |
| CHAT-07 chat search | MVP PostgreSQL search requires no separate cloud search resource. |
| CHAT-08 archive and pin | No additional Azure resource is required. |
| CHAT-09 privacy and access control | External ID settings, fail-closed production gate, private PostgreSQL/Blob access, HTTPS ingress, managed identities, Key Vault references, and scoped new RBAC are provided. Existing broad Blob assignments remain documented security debt. |
| CHAT-10 offline delivery and retries | Durable Service Bus entities, duplicate detection, dead-lettering, a dedicated worker, minimum production replicas, diagnostics, and backlog/dead-letter alerts are provided. Client queueing and cursor recovery remain application responsibilities. |
| CHAT-11 account deletion and retention | The Core worker supplies execution capacity. A privacy-retention queue is intentionally absent until a real consumer exists; the current design may use PostgreSQL background jobs instead. |
| CHAT-12 history on a new device | Private PostgreSQL, production zone-redundant high availability, 35-day backups, and durable API hosting are provided. Restore policy and cursor synchronization remain application responsibilities. |
| CHAT-13 failed-message and retry states | Service Bus retry/dead-letter infrastructure is provided for backend events. User-visible retry state belongs to Core and mobile clients. |
| CHAT-14 basic chat interface | No additional Azure infrastructure is required. |

SignalR, Notification Hubs, and Content Safety are provisioned before their consumers so the Core and mobile implementations can integrate against stable resource coordinates. Provisioning alone does not complete CHAT-01, CHAT-02, CHAT-04, or content-safety enforcement.

## APNS and FCM credentials

Terraform creates the namespace, hub, diagnostics, sender RBAC, and the following reserved secret names, but does not accept or configure provider credentials:

- `notification-hubs-apns-credential`
- `notification-hubs-fcm-v1-credential`

For each environment, a protected operator must:

1. Store the APNS token credential and FCM v1 service-account credential under those names in that environment's Key Vault. Never put them in tfvars, GitHub variables, plan summaries, outputs, or source.
2. Configure the matching Notification Hub through an approved protected credential procedure (Portal or a separately reviewed secret-consuming workflow). Provider limitations mean this remains outside Terraform state.
3. Confirm the Core worker identity has only `Azure Notification Hubs Data Sender`, then send a non-sensitive test notification.
4. Verify failed-send and invalid-token diagnostics and alerts, and remove invalid device registrations in the application workflow.

Use separate APNS keys/FCM projects and Key Vault secrets for dev and production. Rotation must update Key Vault and the provider configuration without revealing values in logs.

## Phase 2 files

`chat-files` remains private, behind the Storage private endpoint, with public blob access and shared-key access disabled. The Core worker receives container-scoped managed-identity access; the Core API retains its pre-existing storage-account assignment pending a separately reviewed RBAC migration. No attachment endpoint, public download URL, or delivery behavior is added in this phase. A later attachment design must add quarantine, malware/content-safety verdict enforcement, authorized short-lived download issuance, retention/deletion, and audit evidence before attachments are exposed. Enabling Azure Content Safety alone does not complete that boundary.


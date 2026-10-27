# Temporary unauthenticated API risk

**Status:** accepted temporary MVP security risk  
**Review date:** 2026-10-23  
**Scope:** current Core/NLP application images, Swagger, health endpoints, and development identity shortcuts

Microsoft Entra External ID Email OTP, Google, and Apple protect only the mobile sign-up/sign-in experience. Core API and NLP API remain directly callable without authentication or authorization. Swagger remains usable without a token. An `Authorization` header supplied by the mobile application is currently ignored.

Do not represent the current system as API-protected. This exception must be reviewed on 2026-10-23 and remediated after October 22, 2026, or earlier if delivery capacity permits.

Terraform injects the External ID authority, tenant, client ID, audience, issuer, scope, and optional roles, but it does not block production deployment when `core_authentication_enforced=false`. That flag is an application enforcement signal, not authentication by itself. The current Core source does not consume this contract and still honors `X-Member-Id`; deploying it to production therefore retains this explicitly accepted security debt until the application is remediated.

## Core API

- Enable Microsoft Entra JWT bearer validation.
- Validate token signature, issuer, audience, and expiration.
- Require the delegated `access_as_user` scope.
- Derive external identity from the immutable `iss` + `sub` pair.
- Link the external identity to the OLGA member.
- Add authenticated-member ownership checks.
- Protect member, mobile, matching, connection, chat, notification, location, and file endpoints.
- Protect administrative endpoints with roles and stronger authentication.

## NLP API

- Remove public accessibility where practical.
- Permit calls only from Core API and authorized workers.
- Add managed identity or service-token validation.
- Add an application permission such as `nlp.invoke`.
- Apply request-size and rate controls.

## Operations and verification

- Remove development identity shortcuts.
- Protect or disable Swagger in prd.
- Add negative authentication tests.
- Add object-ownership authorization tests.
- Make startup fail in Production if JWT enforcement is absent or the MVP member selector is enabled.
- Confirm unauthenticated requests are rejected after enforcement.
- Verify logs and telemetry redact authorization headers, access/refresh tokens, authorization codes, OTP values, and mask email/mobile values.
- Review per-environment budget, traffic, failure, and latency alerts.

## Legacy Blob RBAC

The existing Core API, NLP API, and NLP worker retain storage-account-scoped `Storage Blob Data Contributor` assignments so this chat-infrastructure rollout does not revoke permissions from deployed workloads. The new Core worker uses container-scoped assignments for `profile-images-pending`, `profile-images`, and `chat-files`. After each existing workload's Blob usage is confirmed, replace its broad assignment with explicitly required container scopes in a separate staged migration.

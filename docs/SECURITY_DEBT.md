# Temporary unauthenticated API risk

**Status:** accepted temporary MVP security risk  
**Review date:** 2026-10-23  
**Scope:** Core API, NLP API, Swagger, health endpoints, and current development identity shortcuts

Microsoft Entra External ID email OTP protects only the mobile sign-up/sign-in experience. Core API and NLP API remain directly callable without authentication or authorization. Swagger remains usable without a token. An `Authorization` header supplied by the mobile application is currently ignored.

Do not represent the current system as API-protected. This exception must be reviewed on 2026-10-23 and remediated after October 22, 2026, or earlier if delivery capacity permits.

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
- Confirm unauthenticated requests are rejected after enforcement.
- Verify logs and telemetry redact authorization headers, access/refresh tokens, authorization codes, OTP values, and mask email/mobile values.
- Review per-environment budget, traffic, failure, and latency alerts.

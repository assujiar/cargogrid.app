# {{DOMAIN}} — API Reference

**Template ID:** `CG-DOCS-API-001`
**Template version:** `0.1.0` (established `CG-S5-PH0-013`, Prompt 92)
**Audience:** External/internal integrator — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `{{DRAFT | ACTIVE | SUPERSEDED}}`
**Owner:** `{{ROLE_OR_TEAM}}`
**Since:** Phase `{{PHASE_NUMBER}}` / API version `{{VERSION}}`
**Source contract:** `server/contracts/{{DOMAIN}}/` (`docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md` §4), `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md`

> Generate/verify every endpoint entry against the real `server/contracts/<domain>/` type/validator — do not hand-author an endpoint shape that has no corresponding contract file (`AGENTS.md` "Do not add ... fake API responses").

## 1. Authentication and authorization

`{{AUTH_MECHANISM}}` — every endpoint below enforces tenant/role/scope authorization server-side (`AGENTS.md`), restated per-endpoint in §3, not assumed globally.

## 2. Versioning and compatibility

REST `/v1` / GraphQL surface per `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` §11's deprecation-overlap-window policy. Deprecated paths/fields are listed in §5, with their removal date — never silently removed.

## 3. Endpoints

### `{{METHOD}} {{PATH}}`

- **Purpose:** `{{PURPOSE}}`
- **Auth/scope required:** `{{ROLE_SCOPE}}`
- **Request:** `{{SCHEMA_REF}}`
- **Response (success):** `{{SCHEMA_REF}}`
- **Response (error):** `{{ERROR_CODES_AND_MEANING}}`
- **Idempotency:** `{{IDEMPOTENT_YES_NO_AND_KEY_STRATEGY}}` (`AGENTS.md` "Retriable mutations and deliveries require idempotency")
- **Rate limit / pagination:** `{{DETAILS}}`
- **Example (synthetic data only):** `{{REQUEST_RESPONSE_EXAMPLE}}`

## 4. Webhooks (if applicable)

| Event | Payload schema | Retry/backoff | DLQ |
|---|---|---|---|
| `{{EVENT}}` | `{{SCHEMA_REF}}` | `{{POLICY}}` | `{{YES/NO}}` |

## 5. Deprecations

| Path/field | Deprecated since | Removal date | Migration guidance |
|---|---|---|---|
| `{{PATH_OR_FIELD}}` | `{{DATE}}` | `{{DATE}}` | `{{GUIDANCE}}` |

## 6. Changelog

| Date | Version | Change | Author |
|---|---|---|---|
| `{{DATE}}` | `0.1.0` | Initial | `{{AUTHOR}}` |

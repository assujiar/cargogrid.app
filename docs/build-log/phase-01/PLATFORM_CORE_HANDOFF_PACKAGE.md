# Phase 1 (Platform Core) → Phase 2 (Commercial) Entry Package

**Produced by:** `CG-S6-PLT-036` (Prompt 139 — Platform Core Documentation and Handoff)
**Audience:** an independent Phase 2 agent with **zero prior context** from this build session — every fact below is either directly cited to a `VERIFIED` document or explicitly marked as this checkpoint's own reconciliation.
**Status of this package itself:** complete pending one external precondition — `CG-S6-PLT-037` (Prompt 140, Platform Core Closure Verification) has not yet run. **Nothing in this document should be read as `PHASE_1_VERIFIED` being set** — only Prompt 140 may set that (`140_PLATFORM_CORE_CLOSURE_VERIFICATION_PROMPT.md`: "Set `PHASE_1_VERIFIED` only if all mandatory runtime checks pass").

This is a **new, self-contained artifact**, distinct from `docs/runtime/HANDOFF.md` (which remains the intra-Phase-1, checkpoint-to-checkpoint runtime handoff and retains its own incident-history narrative from Phase 0). This package exists specifically for the "fresh Phase 2 agent reconstructs Platform Core and starts the exact eligible Phase 2 task safely" flow named in Prompt 139 §21, mirroring `docs/build-log/phase-00/PHASE0_HANDOFF_PACKAGE.md`'s own precedent one level up.

## 1. Verified dependencies (what Phase 2 may rely on as fact)

| Closure | Status | Evidence |
|---|---|---|
| Phase 0 — Discovery and Foundation | `PHASE_0_VERIFIED` | `docs/build-log/phase-00/PHASE0_CLOSURE_REPORT.md` |
| Platform Core kickoff (`104`, `CG-S6-PLT-001`) | `VERIFIED` | `docs/build-log/phase-01/00_PLATFORM_CORE_WBS.md`, `00_PLATFORM_CORE_EXECUTION_INDEX.md` row `001` |
| 32 Platform Core capability tasks (`105`–`136`, `CG-S6-PLT-002..033`) | All `VERIFIED` | `docs/runtime/TASK_LEDGER.md`; individual build logs `docs/build-log/phase-01/PLT-105.md`–`PLT-136.md` |
| Integrated Platform Core Verification (`137`, `CG-S6-PLT-034`) | `VERIFIED` | `docs/build-log/phase-01/PLT-137.md` |
| Tenant/Security/Platform Hardening (`138`, `CG-S6-PLT-035`) | `VERIFIED` | `docs/build-log/phase-01/PLT-138.md` |
| Platform Core Documentation and Handoff (`139`, `CG-S6-PLT-036`, this checkpoint) | `IN_PROGRESS` → `VERIFIED` on this checkpoint's own close | This document + `docs/build-log/phase-01/PLT-139.md` |
| Platform Core Closure Verification (`140`, `CG-S6-PLT-037`) | `NOT_STARTED` — the one remaining gate before `PHASE_1_VERIFIED` | `140_PLATFORM_CORE_CLOSURE_VERIFICATION_PROMPT.md` |

**Domain-code status:** zero Commercial-domain (or any later-phase) business code exists anywhere in this repository. Everything listed in §2 below is platform kernel, portal shell, or verification/hardening evidence — not a Commercial feature (§8 confirms this directly).

## 2. Preserved assets (what already exists — do not recreate)

### 2.1 Database (32 migrations, `supabase/migrations/`)

Every migration lives under `app` schema ownership (`ADR-CAND-ARCH-001`), with RLS enabled on every tenant-scoped table and the `ERR-2026-004` per-migration convention (`revoke execute on all functions in schema app from public;` before role-specific grants) present in every migration since `PLT-118` and independently re-confirmed at `PLT-137`'s own traceability audit.

| Capability | Migration | Key tables/functions |
|---|---|---|
| Tenant Provisioning/Lifecycle (`105`) | `20260716075355_create_tenants.sql` | `app.tenants`, `provision_tenant`, `transition_tenant_status` |
| Entitlement (`106`) | `20260716094432_create_entitlements.sql` | `app.entitlement_packages`/`tenant_entitlements`, `evaluate_entitlement` |
| Auth Identity (`107`) | `20260716095343_link_auth_identities.sql` | `app.tenant_user_identities` |
| Principal Membership / Four-Layer Access Context (`108`) | `20260716100825_create_principal_memberships.sql` | `app.principal_memberships`, `resolve_access_context` (documentation hardened at `PLT-138`) |
| Org Hierarchy (`109`) | `20260716101726_create_org_units.sql` | `app.org_units`, `create_org_unit`, move/deactivate |
| User Lifecycle (`110`) | `20260716102620_create_users.sql` | `app.users`, `invite_user`, `transition_user_status` |
| Role/Permission Builder (`111`) | `20260716103445_create_roles_permissions.sql` | `app.roles`/`role_versions`/`permissions`, `create_role`, `assign_role` |
| RBAC Enforcement (`112`) | `20260716104519_create_rbac_evaluator.sql` | evaluator functions |
| RLS Tenant Policy Foundation (`113`) | `20260716105512_create_rls_tenant_policies.sql` | `has_active_tenant_membership`, `is_supreme_admin` |
| Field/Record Access (`114`) | `20260716110430_create_field_record_access.sql` | `app.users_directory` (tenant-isolation bug found+fixed at `PLT-116`, regression-guarded since) |
| Support Access/Impersonation (`115`) | `20260716111315_create_support_access.sql` | support-grant functions |
| Audit Trail (`116`) | `20260716113048_create_audit_trail.sql` | `app.audit_logs`, `capture_audit_event`, `query_audit_logs`/`export_audit_logs` |
| White-Label (`117`) | `20260717090512_create_white_label.sql` | `app.tenant_brand_versions`, `evaluate_tenant_brand` |
| `PUBLIC` execute revocation (`ERR-2026-004` fix) | `20260717095000_revoke_default_public_function_execute.sql` | repository-wide privilege remediation |
| Custom Domain (`118`) | `20260717103015_create_custom_domain.sql` | `app.tenant_custom_domains` |
| Localization (`119`) | `20260717112000_create_localization.sql` | `app.tenant_locale_versions`, `resolve_locale_context` |
| Master Data (`120`) | `20260717120000_create_master_data.sql` | `app.master_types`/`master_records` |
| Configuration Engine (`121`) | `20260717130000_create_configuration_engine.sql` | `app.config_types`/`objects`/`versions`/`items`, `resolve_config` — the shared engine `122`–`133` all reuse |
| Workflow Engine (`122`) | `20260717140000_create_workflow_engine.sql` | `app.workflow_instances`, `start_workflow_instance`, `transition_workflow_instance` |
| Approval Engine (`123`) | `20260719090000_create_approval_engine.sql` | `app.approval_requests` |
| Status Engine (`124`) | `20260719100000_create_status_engine.sql` | `app.status_sets`/`canonical_statuses` |
| Numbering Engine (`125`) | `20260719110000_create_numbering_engine.sql` | `app.numbering_counters`/`allocations` |
| Form/Custom-Field Builder (`126`) | `20260719120000_create_form_custom_field_builder.sql` | `app.form_registry`, `custom_field_values` |
| Notification Engine (`127`) | `20260719130000_create_notification_engine.sql` | `app.notifications`, `queue_notification` |
| Document/File Engine (`128`) | `20260719140000_create_document_file_engine.sql` | `app.files`, `initiate_file_upload`, `authorize_file_access` |
| API Key/Webhook Primitives (`129`) | `20260719150000_create_api_key_webhook_primitives.sql` | `app.api_keys`/`webhook_endpoints`, `authenticate_api_key`, `verify_webhook_signature` |
| REST/GraphQL API Foundation (`130`) | `20260719160000_create_api_foundation.sql` | `app.api_logs`, `record_api_request` — **contract/logging foundation only, no live HTTP route exists** |
| Import/Export Job Framework (`131`) | `20260719170000_create_import_export_job_framework.sql` | `app.jobs`(import/export), `create_import_export_job` |
| Background Job Framework (`132`) | `20260719180000_create_background_job_framework.sql` | `app.jobs` widened to 10 job types, `claim_next_job`/`heartbeat_job`/`complete_job`, `app.event_logs` outbox |
| Feature Flags (`133`) | `20260721090000_create_feature_flags_platform.sql` | `app.feature_flags`, `evaluate_feature_flag` (reuses Configuration Engine) |
| PostGIS/Spatial Foundation (`134`) | `20260722090000_enable_postgis_spatial_foundation.sql` | `geojson_point_to_geography`, `bounded_st_dwithin` (500km cap, `ADR-0014`) — **utility functions only, no tenant-owned spatial column exists yet** (deferred to Phase 3 per `05_DATABASE_SCHEMA_WORKSTREAM.md` line 108) |
| Tenant/Security/Platform Hardening (`138`) | `20260722130000_harden_resolve_access_context_documentation.sql` | comment-only, zero behavioral change |

**Tenant Admin Portal (`135`) and Supreme Admin Portal (`136`) introduce zero migrations** — both read exclusively through the RLS-scoped/service-role client pair against tables already listed above.

### 2.2 Application code (`app/`, `lib/`, `server/`, `components/` — first created at `PLT-105`/`135`)

- **`server/contracts/<domain>/`** — Zod schemas for every capability's own public shape (created incrementally per `00_PLATFORM_CORE_WBS.md` §3's own convention).
- **`server/queries/`/`server/mutations/`** — typed client wrappers per capability, each against the two-client architecture below.
- **`lib/supabase/{server,service-role}.ts`** (`PLT-135`) — the two Supabase client factories every portal reuses: RLS-scoped `authenticated` client (session/tenant reads RLS already scopes correctly) vs. server-only `service_role` client (used exactly once per portal, for `resolve_access_context`, the one `service_role`-only RPC).
- **`lib/portal/{tenant-admin-guard,supreme-admin-guard}.ts`(+deps+resolve helpers)** — pure, unit-tested, dependency-injected portal-entry guards (5-outcome and 3-outcome discriminated unions respectively).
- **`components/ui/{button,banner}.tsx`** — the two `components/ui/` primitives Platform Core needed (Radix copy-in pattern, `ADR-0005`); CargoGrid's own brand color/logo/font remain genuinely undecided (`docs/standards/DESIGN_SYSTEM.md` §3) — `primary`/`secondary` CSS variables are a disclosed placeholder mapped to neutral tokens, not a fabricated brand.
- **`app/(public)/login`** — the one shared, portal-agnostic sign-in entry point (real `signInWithPassword` Server Action); organization field optional (blank → Supreme, filled → tenant slug).
- **`app/(tenant)/[tenantSlug]/admin`** — Tenant Admin shell + Home + read-only Users list (`PLT-135`).
- **`app/(supreme)/supreme`** — Supreme Admin shell + Home + read-only global tenant list, with a persistent, structural RPD-022 disclosure banner (`PLT-136`).

**No route beyond these two portal shells exists.** No live REST/GraphQL HTTP endpoint exists anywhere (`PLT-130` is a contract/logging foundation only). No Commercial-domain UI/route/table exists (§8).

### 2.3 Verification and hardening evidence (`scripts/db-tests/`, 32 files)

30 individual-capability db-test files (one per capability `105`–`134`, each independently exhaustive for its own scope) plus two cross-cutting files: `platform-core-integrated-verification.sql` (`PLT-137`, 14 scenario groups composing 12 capabilities through one two-tenant golden path) and `tenant-security-hardening.sql` (`PLT-138`, 5 scenario groups, the `PLT-137` finding's own regression evidence). **394 total scenario groups**, all passing together against one disposable, sequentially-migrated database in a single `pnpm run db:test` invocation — the real, current integration baseline.

### 2.4 ADRs (14 ratified, `docs/adr/`)

`ADR-0001`–`ADR-0010` from Phase 0; `ADR-0011` (webhook retry/backoff/DLQ, `PLT-129`), `ADR-0012` (GraphQL depth/complexity limits, `PLT-130`), `ADR-0013` (job queue backoff/lease/DLQ defaults, `PLT-132`), `ADR-0014` (PostGIS conventions, `PLT-134`) from Platform Core. See `docs/adr/README.md` §6 for the full index and §5.2 for every `ADR-CAND-ARCH-*` candidate's current status — **three stale Phase-1 references corrected this checkpoint** (§7 below).

## 3. Exact first eligible prompt (contingent, not yet active)

**Prompt 142 — Commercial WBS and Runtime Kickoff** (`CG-S7-COM-001`, `docs/ai-agent-build-prompt-package/07-phase-02-commercial/142_COMMERCIAL_WBS_RUNTIME_KICKOFF_PROMPT.md`). Mirroring Prompt 104's own pattern one phase up, its own first required task is expected to be "Reconfirm Phase 0/Phase 1 closure reports at one active checkpoint" before proceeding — i.e. it re-validates `PHASE_1_VERIFIED` itself, so this package does not need to (and must not) assert that flag is set. **It becomes eligible only after `CG-S6-PLT-037` (Prompt 140) completes and records `PHASE_1_VERIFIED`** — until then, the correct next action for any agent reading this package is Prompt 140, not Prompt 142.

## 4. Known issues carried into Phase 2 (from `docs/runtime/KNOWN_ISSUES.md`, current state)

| ID | Status | Carries into Phase 2 as |
|---|---|---|
| `ISS-2026-005` | `OPEN`, Low | A documentation-completeness gap in `CHANGE_MANIFEST.md` (Prompts 83–90 entries never backfilled, Phase 0-scoped) — does not affect any Platform Core code, schema, or decision; owner DevEx, pick up opportunistically |
| `ISS-2026-007` | `OPEN`, Medium | No working automated dependency/supply-chain audit gate (`pnpm audit` calls a retired npm endpoint at pnpm `10.33.0`) — re-attempt once pnpm ships bulk-endpoint support; `pnpm install --frozen-lockfile` remains the real, working deterministic-install control in the interim |
| `ISS-2026-006` | `ACCEPTED_RISK`, Low | 4 historical citations to deleted plural build-log paths, excused via a named allowlist — no action needed |
| All others (`ISS-2026-001..004`, `008`) | `RESOLVED` | No action needed |

**No new issue was opened anywhere in Platform Core** (`PLT-105`–`138`). **No Critical or unresolved High-severity issue exists.** Neither open issue blocks any Phase 2 gate or decision.

**Errors:** `ERR-2026-001..003` (Phase 0) all `RECOVERED`/`SUPERSEDED`. `ERR-2026-004` (repository-wide `PUBLIC` EXECUTE grant, found and fixed at `PLT-118`) is `RECOVERED`, with its per-migration convention independently re-confirmed intact across all 32 migrations at `PLT-137`'s own traceability audit. **Zero `OPEN` error.**

## 5. Environment commands (verified working, this checkpoint)

```
pnpm install --frozen-lockfile   # deterministic install
pnpm run typecheck               # tsc --noEmit
pnpm run lint                    # eslint .
pnpm run test                    # node:test, scripts/**|server/**|lib/**|tests/**/*.test.ts
pnpm run test:coverage           # same, with --experimental-test-coverage
pnpm run test:e2e                # Playwright + axe-core (sandbox chrome-headless-shell gap, see §6)
pnpm run db:test                 # bash scripts/db-tests/run.sh -- 32 migrations + 32 test files, disposable DB
pnpm run docs:check              # scripts/docs/check-doc-links.ts
pnpm run security:check          # scripts/security/check-secrets.ts
pnpm run data-classification:check
pnpm run threat-model:check
pnpm run standards:check         # scripts/standards/check-suppressions.ts
pnpm run git:check               # scripts/git/check-worktree-collision.ts + check-branch-name.ts
pnpm run git:check-paths         # scripts/git/check-protected-paths.ts
pnpm run preflight               # scripts/preflight-env-check.ts -- fails closed, no live environment
```

`db:test` additionally requires a reachable Postgres with PostGIS available (`postgresql-<major>-postgis-3` locally; CI uses `postgis/postgis:17-3.4`, `.github/workflows/ci.yml`) — a real runtime dependency since `PLT-134`. All gate results as of this checkpoint: see `docs/build-log/phase-01/PLT-139.md` §6 (live gate run) — do not treat any specific `node:test`/`db:test` count in this document as durable; read the live gate output.

## 6. Residual risks Phase 2 should be aware of (not blocking, all already-disclosed)

- **RPD-022** (Supreme Admin absolute CRUD) — no tamper-proof/immutability claim may ever be made; disclosed structurally in the Supreme portal's own persistent UI banner (`PLT-136`), not documentation alone. Phase 2's first audit/finance-adjacent feature must carry the same disclosure, not silently assume immutability.
- **No live Supabase project exists anywhere** — both portals' guards were verified directly against a completely unreachable backend (`307`-redirect fail-safe, never a `500`), but a real sign-in flow, real RLS-against-a-live-database session, and real `next build`/deploy pipeline all remain `NOT_RUN`. Phase 2's own environment-provisioning work (if any is still pending) is a precondition for any of that becoming real, not something this package can substitute for.
- **`pnpm run test:e2e` has a persistent, disclosed sandbox condition** — `chrome-headless-shell` executable missing at `/opt/pw-browsers/...` — present at every checkpoint since `PLT-117`, re-confirmed unchanged through `PLT-138`. Every E2E spec's own source and `webServer` wiring is independently verified reaching the real dev server before failing only at this known step. Phase 2 should not assume this is a newly-introduced gap.
- **`app.resolve_access_context`'s tenant-qualified branch has no Supreme Admin shortcut** (documented, not fixed-as-a-bug, at `PLT-138`) — a global-only Supreme Admin fails closed (`inactive_identity_link`) if ever called with an explicit tenant id; the only real caller (`lib/portal/supreme-admin-guard.ts`) never does this. Any future Phase 2 caller of the tenant-qualified form must account for this boundary, not assume Supreme Admin bypasses it.
- **`app.claim_next_job()`'s worker-claim pool is deliberately tenant-agnostic** (`PLT-132`/re-confirmed `PLT-137`) — a shared worker fleet serves every tenant by architecture, not a defect; `app.jobs`' own RLS still isolates *viewing* per tenant correctly.
- **Package/subscription management, platform config UI, support-grant administration UI, audit-log browsing UI, and system health UI** are all real, already-shipped *backend* capability (`106`, `115`, `116`, `121`) with **no UI built yet** — deliberately bounded out of both portal shells (`PLT-135`/`136` §3), per `09_UX_DESIGN_SYSTEM_WORKSTREAM.md`'s own atomic backlog placing them as separate, later slices. Phase 2 (or a later Platform UI slice) should build these against the already-verified backend, not assume they need re-design.
- **The bounded rule-expression evaluator was deliberately not built** (`PLT-121` §25; `ADR-CAND-ARCH-014`/`015`, corrected this checkpoint, §7) — `app.validate_config_value()` enforces structural/injection safety on every config value, but no config value is ever *executed* as a rule anywhere in Platform Core. The first Phase 2+ capability that needs real rule-expression evaluation must design and build this from scratch, informed by (not assuming) the existing structural-safety groundwork.
- **8 `ADR-CAND-ARCH-*` candidates remain genuinely open**, most now correctly re-scoped to Phase 2+ or later (`012` now correctly Phase 2 Commercial schema, `013` Phase 3, `014`/`015` Phase 2+ rule evaluator, `017`/`018` partially resolved with a numeric sub-question still open, `019` DevOps deployment ordering, `027` hosting/CDN — see `docs/adr/README.md` §5.2). Phase 2 should resolve each at its own owning task, not assume a default.

## 7. Corrections made this checkpoint (disclosed, not hidden)

Three stale `ADR-CAND-ARCH-*` "Owning task" references in `docs/adr/README.md` §5.2 were found and fixed while reconciling this package against live evidence:

1. **`ADR-CAND-ARCH-012`** ("Phase 1 schema (Prompt 120+)") — `customers` is a Commercial-domain table; Platform Core closed without building any Commercial schema (confirmed: no `customers`/CRM table exists in any of the 32 migrations). Corrected to "Phase 2 Commercial schema."
2. **`ADR-CAND-ARCH-014`/`015`** ("Config engine (Phase 1)") — `PLT-121` (`docs/build-log/phase-01/PLT-121.md` §25) explicitly deferred the bounded rule-expression evaluator itself to Phase 2+, since no business rule with real runtime semantics exists anywhere in Platform Core. Corrected to name that deferral directly.

None of the three was a missed Platform Core obligation — each was always correctly out of Platform Core's own scope; the "Owning task" column simply had not been updated to say so. No `ADR-CAND-ARCH-*` status (`PROPOSED`/`BLOCKED`/`ACCEPTED`) itself changed, only the "owning task" citation.

## 8. Forbidden-scope confirmation (Prompt 139 §12/§24, re-checked this checkpoint)

`git ls-files app/ lib/ server/ components/ | grep -iE "customer|lead|prospect|quote|shipment|invoice|payment|ticket|hris|payroll"` returns nothing — zero Commercial (or any later-phase) domain concept exists anywhere in application code. No tenant fork, no generic multi-provider abstraction exists (`docs/runtime/KNOWN_ISSUES.md` §2 `RPD-038` remains the standing discipline, unexercised so far since no external integration has been built). Every one of the 32 migrations is platform-kernel-scoped (tenants, entitlement, identity, RBAC/RLS, audit, config/workflow/approval/status/numbering/form/notification/document/API-key/webhook/job/flag/spatial engines) or portal-shell-scoped — none implements a CargoGrid business capability.

## 9. Fresh-context reconstruction check (Prompt 139 §21/§28, rehearsed this checkpoint)

Reading only this document plus its cited paths (no other session context), an agent can determine: what phase the repository is in (Phase 1, pending Prompt 140 closure), what exists on disk (§2), what is decided vs. still open (§2.4, §6, §7), what commands verify the current state (§5), what the exact next prompt is once Phase 1 formally closes (§3), and what residual risks/design boundaries to respect rather than "fix" without re-reading history first (§6). This satisfies Prompt 139 §21's "fresh Phase 2 agent reconstructs Platform Core and safely starts exact Commercial task" — with the one correct caveat that the actual next action right now is Prompt 140, not Prompt 142 (§3).

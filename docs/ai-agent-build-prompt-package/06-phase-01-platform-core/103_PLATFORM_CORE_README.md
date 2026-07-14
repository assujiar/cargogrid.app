# Step 6 — Phase 1 Platform Core Prompt Package

**Document ID:** `CG-AABPP-PLT-103`  
**Version:** `0.7.0`  
**Status:** `FINAL_FOR_STEP`  
**Package authorization:** Prompt generation only. Platform Core runtime implementation is not executed or implied.

## 1. Purpose

This package decomposes CargoGrid Platform Core into bounded, dependency-aware implementation prompts for tenant lifecycle, entitlements, identity/access, organization/user administration, shared engines, APIs/jobs/files/audit, spatial foundations, and the Tenant Admin/Supreme Admin portals.

## 2. Runtime entry gate

Before Prompt 104 or any Prompt 105–139:

1. Step 2 runtime discovery is `RUNTIME_DISCOVERY_VERIFIED`.
2. Step 3 runtime architecture is `RUNTIME_ARCHITECTURE_VERIFIED`.
3. Step 5 runtime closure is `PHASE_0_VERIFIED` at the active repository checkpoint.
4. Step 4 reusable library is package-verified.
5. Phase 1 WBS/traceability, branch/worktree ownership, exact paths, environment and baselines are current.

If any gate fails, set `PHASE_1_BLOCKED`, update ledgers/handoff and stop. `STEP_6_PACKAGE_COMPLETE` is not Platform Core runtime completion.

## 3. Required hierarchy and atomicity

Prompt 104 instantiates:

`Phase 1 → Workstream → Epic → Capability → Feature slice → Atomic implementation task → Verification task → Hardening task → Documentation task → Phase closure task`.

Prompts 105–136 each represent one bounded capability slice. Prompt 137 verifies integration, Prompt 138 hardens tenant/security/platform risks, Prompt 139 reconciles documentation/handoff, and Prompt 140 closes the phase.

Default boundary remains one slice/module/branch/objective, normally 1–3 migrations and 5–15 changed files. Prompt 104 must split any profile that exceeds the verified repository boundary.

## 4. Capability catalogue and dependency order

| Order | ID | Capability | Primary dependencies |
|---:|---|---|---|
| 0 | PLT-104 | WBS/runtime kickoff | `PHASE_0_VERIFIED` |
| 1 | PLT-105 | Tenant provisioning and lifecycle | PLT-104 |
| 2 | PLT-106 | Subscription/module/feature entitlement | PLT-105 |
| 3 | PLT-107 | Supabase Auth integration | PLT-104..106 |
| 4 | PLT-108 | Four-layer identity/access context | PLT-105..107 |
| 5 | PLT-109 | Organization/company/branch/department/team hierarchy | PLT-105,108 |
| 6 | PLT-110 | User lifecycle | PLT-107..109 |
| 7 | PLT-111 | Role and permission builder | PLT-108..110 |
| 8 | PLT-112 | RBAC enforcement | PLT-111 |
| 9 | PLT-113 | RLS tenant policy foundation | PLT-105,108,112 |
| 10 | PLT-114 | Field-level and record-level access | PLT-112..113 |
| 11 | PLT-115 | Support access and impersonation control | PLT-107,112..114 |
| 12 | PLT-116 | Audit trail foundation | PLT-105,107..115 |
| 13 | PLT-117 | White-label foundation | PLT-105..106,116 |
| 14 | PLT-118 | Custom domain | PLT-107,117 |
| 15 | PLT-119 | Localization | PLT-117 |
| 16 | PLT-120 | Master data foundation | PLT-105,109,113..116 |
| 17 | PLT-121 | Configuration engine | PLT-105,109,112..116,120 |
| 18 | PLT-122 | Workflow engine | PLT-121 |
| 19 | PLT-123 | Approval engine | PLT-111..116,122 |
| 20 | PLT-124 | Status engine | PLT-121..123 |
| 21 | PLT-125 | Numbering engine | PLT-105,109,121,124 |
| 22 | PLT-126 | Form and custom-field builder | PLT-112..114,121,124 |
| 23 | PLT-127 | Notification engine | PLT-107,121..124 |
| 24 | PLT-128 | Document/file engine | PLT-113..116,121,127 |
| 25 | PLT-129 | API key and webhook primitives | PLT-107,112..116,127 |
| 26 | PLT-130 | REST/GraphQL platform API foundation | PLT-112..116,120..129 |
| 27 | PLT-131 | Import/export job framework | PLT-113..116,120,128,130 |
| 28 | PLT-132 | Background job framework | PLT-113,116,121,127..131 |
| 29 | PLT-133 | Feature flags | PLT-106,112,116,121,132 |
| 30 | PLT-134 | PostGIS/spatial foundation | PLT-105,109,113,116,120 |
| 31 | PLT-135 | Tenant Admin portal | PLT-106..134 required subset |
| 32 | PLT-136 | Supreme Admin portal | PLT-105..135 required subset |
| 33 | PLT-137 | Integrated Platform Core verification | PLT-105..136 |
| 34 | PLT-138 | Tenant/security/platform hardening | PLT-137 |
| 35 | PLT-139 | Documentation and handoff | PLT-138 |
| 36 | PLT-140 | Phase 1 closure | PLT-139 |

Prompt 104 may enable parallel lanes only when schema, contracts, files, access primitives and test environments do not collide.

## 5. Binding Platform Core rules

- One shared multi-tenant codebase; no tenant fork.
- PostgreSQL/Supabase is authoritative; every tenant table uses tenant-aware keys, RLS, indexes and negative isolation tests.
- Four layers are explicit: Supreme Admin, Tenant Admin, tenant organizational users, and customer users. Layer membership never replaces permission/scope checks.
- Supreme Admin retains literal absolute CRUD, including audit/ledger/final records; prompts must disclose that immutability/tamper-proof guarantees are impossible under RPD-022.
- REST and GraphQL coexist over shared domain services with identical validation/access/audit/idempotency semantics.
- PostgreSQL durable queue is the first job architecture; separate workers are threshold-driven.
- PostGIS starts in Platform Core.
- All uploads are private-by-default, malware-scanned/quarantined before availability, tenant/record-aware and delivered by short-lived signed URL.
- Configuration/workflow/approval/status/numbering/forms/notifications are governed versioned engines, never tenant-specific hard-coded code.
- Non-AI external integrations remain custom case-by-case; no generic provider abstraction contrary to RPD-038.
- High-volume reads use server pagination; no transactional `SELECT *`, full browser dataset or unapproved realtime.

## 6. Runtime states

`PHASE_1_NOT_STARTED`, `PHASE_1_IN_PROGRESS`, `PHASE_1_BLOCKED`, `PHASE_1_PARTIALLY_COMPLETE`, `PHASE_1_VERIFIED`, `PHASE_1_ROLLED_BACK`.

Only Prompt 140 may set `PHASE_1_VERIFIED`.

## 7. Package completion

Package completion requires 38 non-empty files, IDs `PLT-103..140`, 35 operational prompts with 36/36 fields, all 32 capabilities, integrated verification/hardening/docs/closure, explicit dependency/next links, and updated controls.

**Next package command:** `LANJUT STEP 7`

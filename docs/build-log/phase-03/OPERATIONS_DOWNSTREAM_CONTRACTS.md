# Phase 3 → Phase 4/5/8 Downstream Contracts

**Produced by:** `CG-S8-OPS-021` (Prompt 187 — Operations Documentation and Handoff), per Prompt 187 §20 task 3: "Create Phase 4 billing-readiness, Phase 5 advanced TMS/WMS and Phase 8 portal contract examples/boundaries."
**Scope note:** unlike Commercial's own single `JOB_ORDER_HANDOFF_CONTRACT.md` (one immutable snapshot, one downstream consumer), Operations exposes **three distinct surfaces to three distinct later phases** with three different shapes — a snapshot-style handoff record (Finance), a direct schema-extension boundary (Advanced TMS/WMS), and a public read-only RPC (Customer Portal). All three are documented in this one file rather than three separate companion documents, since none of them individually approaches the depth of Commercial's own Job Order contract, and grouping them keeps the "what does Operations hand off, and to whom" question answerable from one place.

---

## 1. Phase 4 (Finance) — Billing Readiness contract

**Source of truth:** `supabase/migrations/20260728140000_create_operations_billing_readiness.sql` (`OPS-181`) and `server/contracts/billing-readiness/billing-readiness.ts`. This document explains and exemplifies that contract; it does not redefine it — if this document and the migration/contract file ever disagree, the migration/contract file is authoritative.

### 1.1 What this contract is, and is not

Operations' own scope ends at producing **one versioned, deterministic evidence record** per Job Order — `app.billing_readiness_evaluations`, plus one append-only Finance-handoff record, `app.billing_readiness_handoffs`, once that evidence reaches an effective `ready` status. **No invoice, accounts-receivable, general-ledger, or journal entry exists anywhere in this repository** (`OPS-181`'s own explicit, repeatedly-reinforced disclosure — evidence status only, never a financial posting). Phase 4 (Finance) owns designing and building the actual billing/invoicing domain that *consumes* this evidence record — this contract is Phase 4's own starting input, not a preview of Phase 4's own schema.

### 1.2 How the evidence is produced (API surface)

| Function | Signature | Gate | Behavior |
|---|---|---|---|
| `app.evaluate_billing_readiness` | `(p_job_order_id uuid, p_reevaluation_reason text, p_actor_auth_user_id uuid, p_actor_label text) returns app.billing_readiness_evaluations` | `OPS:Edit` + record-scope | Synchronous, deterministic. First evaluation needs no reason; every subsequent evaluation while a current row exists requires a non-empty `reevaluation_reason`. Always inserts a brand-new version (never overwrites), and always resets any prior override. |
| `app.override_billing_readiness` / `app.revoke_billing_readiness_override` | `(p_job_order_id uuid, p_expected_version integer, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) returns app.billing_readiness_evaluations` | `OPS:Override` + record-scope | Bounded to forcing an evaluated `not_ready` row to an effective `ready` outcome, never the reverse. `effective_status` is a generated column — the raw evidence result (`evaluated_status`) stays visible even while overridden. |
| `app.handoff_billing_readiness` | `(p_job_order_id uuid, p_idempotency_key text, p_actor_auth_user_id uuid, p_actor_label text) returns app.billing_readiness_handoffs` | `OPS:Edit` + record-scope | Requires the current evaluation's `effective_status = 'ready'`. Idempotent on `(tenant_id, job_order_id, idempotency_key)` — a retry with the same key returns the exact same handoff row. |

All three are `authenticated`-granted (tenant-scoped, RLS/RBAC-gated) and `service_role`-granted (for a future Phase 4 worker/integration to read via the service-role client, the same two-client pattern every prior capability uses).

### 1.3 The `BillingReadinessEvaluation` schema (field-by-field)

```typescript
// server/contracts/billing-readiness/billing-readiness.ts
{
  id: string;                    // uuid
  tenantId: string;               // uuid
  jobOrderId: string;             // uuid
  versionNumber: number;          // 1, 2, 3... -- always increases, never overwritten
  isCurrent: boolean;
  evaluatedStatus: "ready" | "not_ready";       // the raw, evidence-based result
  effectiveStatus: "ready" | "not_ready";       // generated column: "ready" while isOverridden, else evaluatedStatus
  blockers: { code: string; [key: string]: unknown }[];  // fixed named codes, e.g. "shipment_not_delivered", "epod_incomplete", "active_exception", "actual_cost_not_approved", "billing_profile_missing"
  evidence: {
    shipmentOrderIds: string[];   // every Shipment Order under this Job Order that evidence was drawn from
    actualCostIds: string[];      // the exact app.shipment_actual_costs rows referenced
    epodCaptureIds: string[];     // the exact app.epod_captures rows referenced
    creditOutcome: string | null; // from app.job_orders.credit_snapshot (Commercial's own pinned snapshot, COM-164)
    jobOrderStatus: string;
  };
  ruleVersion: number;             // fixed placeholder (1) -- no configurable rule engine yet, see §1.5
  isOverridden: boolean;
  overrideReason: string | null;
  overriddenBy: string | null;
  overriddenAt: string | null;     // ISO 8601
  overrideRevokedReason: string | null;
  overrideRevokedBy: string | null;
  overrideRevokedAt: string | null;
  reevaluationReason: string | null;
  supersedesEvaluationId: string | null;  // uuid -- the immediately-prior version, never deleted
  evaluatedByAuthUserId: string;   // uuid
  evaluatedBy: string | null;
  recordVersion: number;
  createdBy: string | null;
  createdAt: string;
  updatedAt: string;
}
```

### 1.4 Full synthetic example (redacted/fictional — no real customer data)

```json
{
  "id": "d4e5f6a7-b8c9-4012-3456-789abcdef012",
  "tenantId": "223e4567-e89b-12d3-a456-426614174000",
  "jobOrderId": "323e4567-e89b-12d3-a456-426614174000",
  "versionNumber": 4,
  "isCurrent": true,
  "evaluatedStatus": "ready",
  "effectiveStatus": "ready",
  "blockers": [],
  "evidence": {
    "shipmentOrderIds": ["423e4567-e89b-12d3-a456-426614174000", "523e4567-e89b-12d3-a456-426614174000"],
    "actualCostIds": ["623e4567-e89b-12d3-a456-426614174000", "723e4567-e89b-12d3-a456-426614174000"],
    "epodCaptureIds": ["823e4567-e89b-12d3-a456-426614174000", "923e4567-e89b-12d3-a456-426614174000"],
    "creditOutcome": "allow",
    "jobOrderStatus": "confirmed"
  },
  "ruleVersion": 1,
  "isOverridden": false,
  "overrideReason": null,
  "overriddenBy": null,
  "overriddenAt": null,
  "overrideRevokedReason": null,
  "overrideRevokedBy": null,
  "overrideRevokedAt": null,
  "reevaluationReason": "exception resolved, all evidence should now be clean",
  "supersedesEvaluationId": "a23e4567-e89b-12d3-a456-426614174000",
  "evaluatedByAuthUserId": "023e4567-e89b-12d3-a456-426614174000",
  "evaluatedBy": "rep",
  "recordVersion": 1,
  "createdBy": "rep",
  "createdAt": "2026-07-28T03:00:00.000Z",
  "updatedAt": "2026-07-28T03:00:00.000Z"
}
```

### 1.5 Compatibility notes

- **Idempotency**: `handoff_billing_readiness` is idempotent on `(tenant_id, job_order_id, idempotency_key)`. Phase 4 may safely retry the same handoff call.
- **Versioning**: `versionNumber`/`isCurrent` never overwrite — a reevaluation always inserts a brand-new row and flips the prior to `isCurrent=false`. Phase 4 should always read `is_current=true` for the authoritative current state, and may walk `supersedesEvaluationId` backward for full history.
- **`ruleVersion` is a fixed placeholder (`1`)** for every row produced through `OPS-186` — no configurable rule-engine table exists yet. Phase 4 needing a configurable readiness rule set (different blocker rules per tenant/contract type) must design this from scratch.
- **Money precision**: no dollar amount appears anywhere in this contract at all — `evidence` references cost/ePOD rows by id only, never a duplicated amount. Phase 4 must read the actual amounts from `app.shipment_actual_costs` directly (respecting its own `OPS:View cost` masking) if it needs them.
- **`blockers` codes are a fixed, named set** (9 codes as of `OPS-181`, see `BILLING_READINESS_BLOCKER_CODES` in the contract file) — Phase 4 should branch on `code`, never parse free text.

### 1.6 Unresolved dependency list (what Phase 4 must still design/build)

1. **The Finance/billing domain itself** — invoice/AR/GL tables, posting logic, RLS, RBAC actions, UI. Nothing here is inherited from Operations beyond this one evidence record.
2. **A real worker or integration path to consume `app.billing_readiness_handoffs`** — no live REST/GraphQL route or background worker reads this table anywhere in this repository today.
3. **A configurable billing-readiness rule engine**, if Phase 4 ever needs tenant-specific or contract-specific readiness rules beyond the current fixed 9-code checklist.
4. **A billing-readiness UI beyond the Job Order detail panel** — the current `BillingReadinessPanel` (`app/(tenant)/[tenantSlug]/operations/job-orders/[jobOrderId]/billing-readiness-panel.tsx`) is Operations' own evidence-status display, not a Finance workspace.

---

## 2. Phase 5 (Advanced TMS/WMS) — extension boundaries

Unlike §1/§3, Phase 5 does not consume a separate snapshot or RPC — it is expected to **directly extend Operations' own already-existing tables and functions in place**, the same way Commercial's own capabilities incrementally extended Platform Core's foundation tables (e.g. quotation versioning widening `app.quotations`, `COM-152`). This section names which surfaces are extension points versus which Phase 5 must build fresh.

### 2.1 Extend in place (do not fork or duplicate)

- **`app.shipment_orders`** (`OPS-169`) — the canonical Shipment Order root. Multi-leg/multi-modal shipments (Prompt package's own Phase 5 scope) should extend this table (e.g. a `parent_shipment_order_id`/`leg_sequence` column pair) rather than create a parallel "advanced shipment" table — the existing lifecycle (`OPS-170`), mode baseline (`OPS-171`), resource assignment (`OPS-172`), milestone tracking (`OPS-173`), dispatch (`OPS-175`), document/ePOD (`OPS-176`/`177`), actual cost (`OPS-178`) and billing readiness (`OPS-181`) machinery all already key off `shipment_order_id` and would need no redesign, only a genuinely new leg-aware read path where relevant.
- **`app.shipment_mode_profiles`** (`OPS-171`) — currently a flat land/air/sea profile per shipment. A real fleet/route-planning capability should extend this shape (or add a sibling table joined 1:1) rather than replace it.
- **`app.resource_assignments`** (`OPS-172`) — already supports `vendor`/`fleet`/`vehicle`/`driver` role types generically via `app.master_records`. Route/load planning and capacity-utilization work (Phase 5's own named scope) should read/write this table directly, not introduce a second assignment concept.
- **`app.milestone_codes`/`app.milestone_events`** (`OPS-173`) — the platform-wide milestone catalogue and event log are already generic (not land/air/sea-specific). Advanced visibility/GPS-telematics integration should ingest into `app.ingest_milestone_event` directly, adding new milestone codes via `app.register_milestone_code` (Supreme-only, idempotent) rather than a parallel event table.

### 2.2 Build fresh (no Operations precedent exists)

- **Warehouse/inventory ledger** — zero warehouse or inventory concept exists anywhere in Operations; this is entirely new schema for Phase 5.
- **Route/load planning, capacity utilization** — Operations' own dispatch (`OPS-175`) is a bounded MVP readiness checklist (status=assigned, an active resource assignment, no blocking exception, a planned pickup time); no route-optimization or capacity-modeling logic exists to extend.
- **Customer inventory access, warehouse billing** — no analog exists in Operations at all.

### 2.3 What NOT to duplicate

`app.milestone_codes` and `app.transaction_lineage_edges`' relation-type/node-type vocabulary are both intentionally bounded, disclosed-scope enums (see `OPERATIONS_HANDOFF_PACKAGE.md` §6) — Phase 5 extending shipment lineage into a multi-leg concept should widen these enums via a new migration (never edit `20260727140000_*.sql`/`20260728170000_*.sql`), following the same "extend via a new migration, never edit an applied one" discipline every Operations checkpoint this phase has followed.

---

## 3. Phase 8 (Customer Portal) — Public Tracking contract

**Source of truth:** `supabase/migrations/20260728130000_create_operations_public_tracking.sql` (`OPS-180`) and `server/queries/public-tracking.ts`. This document explains and exemplifies that contract; it does not redefine it.

### 3.1 What this contract is, and is not

Operations' own scope ends at one read-only, rate-limited, sanitized RPC — `app.lookup_public_shipment_tracking` — the one and only `anon`-granted function across the entire Operations schema. **No live Customer Portal route, customer authentication, or customer-facing dashboard exists anywhere in this repository** — the current `/tracking/[token]` page is a single unauthenticated lookup page, not a portal. Phase 8 (Customer Portal) owns designing and building the actual authenticated customer-facing experience; this RPC is one building block it may reuse, not a preview of Phase 8's own architecture.

### 3.2 How tokens are issued and looked up (API surface)

| Function | Signature | Gate | Behavior |
|---|---|---|---|
| `app.issue_shipment_tracking_token` | `(p_shipment_order_id uuid, p_validity_days integer, p_actor_auth_user_id uuid, p_actor_label text) returns table (token_id uuid, raw_token text, expires_at timestamptz, shipment_order_id uuid)` | `OPS:Edit` + record-scope | Internal-facing (`authenticated`/`service_role` only, never `anon`). Reissuing revokes the prior active token — at most one active token per shipment at a time. `raw_token` is returned exactly once at issuance; only its hash is stored (`app.shipment_tracking_tokens`). |
| `app.revoke_shipment_tracking_token` | `(p_token_id uuid, p_reason text, p_actor_auth_user_id uuid, p_actor_label text) returns app.shipment_tracking_tokens` | `OPS:Edit` + record-scope | Reason mandatory. |
| `app.lookup_public_shipment_tracking` | `(p_raw_token text, p_client_key text) returns table (lookup_status text, shipment_number text, status text, mode text, origin text, destination text, planned_delivery_at timestamptz, current_eta timestamptz, is_delayed boolean, milestones jsonb, epod_available boolean)` | **`anon`-granted, no authentication** | The one public entry point. `lookup_status` is `'ok'` / `'not_found'` / `'invalid'` / `'rate_limited'` — every outcome is a normal returned row, never a raised exception (so the rate-limit attempt log always actually commits). Sanitized: excludes internal-only milestone codes, precise geolocation, vendor identity, and every cost/profitability figure. Wrong/expired/revoked tokens and genuinely unknown tokens are indistinguishable (`not_found`) — existence of a real shipment is never revealed to a failed lookup. |

### 3.3 The sanitized projection shape (field-by-field)

```typescript
// what app.lookup_public_shipment_tracking returns -- server/queries/public-tracking.ts
{
  lookupStatus: "ok" | "not_found" | "invalid" | "rate_limited";
  shipmentNumber: string | null;    // null unless lookupStatus === "ok"
  status: string | null;            // the real app.shipment_orders.status value, passed through directly
  mode: "land" | "air" | "sea" | null;
  origin: string | null;
  destination: string | null;
  plannedDeliveryAt: string | null; // ISO 8601
  currentEta: string | null;        // from app.shipment_milestone_projections, an observed/projected marker, never a predictive algorithm
  isDelayed: boolean | null;
  milestones: { code: string; eventTime: string }[] | null;  // customer-visible codes only -- internal-only codes (e.g. "customs_hold") are filtered out entirely, never masked-in-place
  epodAvailable: boolean | null;     // true once a completed ePOD capture exists -- the capture itself (signature, photos, receiver name) is never exposed here
}
```

### 3.4 Compatibility notes

- **Rate limiting**: a `client_key` (caller-supplied, e.g. a hashed IP or session id) is required; `app.tracking_lookup_attempts` enforces a 10-attempt/15-minute window per `client_key`, returning `lookup_status='rate_limited'` rather than raising. Phase 8 must supply a real, stable `client_key` per browser session/IP — reusing a constant value defeats the rate limit entirely.
- **Token lifecycle**: at most one active token per shipment; issuing a new one silently revokes the prior. Phase 8 should not assume a previously-shared tracking link remains valid indefinitely — it may need to request a fresh token through an authenticated path if building a persistent customer-facing link.
- **No location precision beyond the milestone's own recorded point** — `currentEta`/location are never a live GPS feed; this is milestone-event-driven, not a telematics integration (that is Phase 5's own scope, §2.2).
- **Money is never exposed anywhere in this contract** — not cost, not revenue, not profitability. Phase 8 must never attempt to surface financial data through this RPC; it structurally cannot.

### 3.5 Unresolved dependency list (what Phase 8 must still design/build)

1. **The Customer Portal domain itself** — customer authentication, dashboard, multi-shipment views, notification preferences. Nothing here is inherited from Operations beyond this one public RPC.
2. **A durable, authenticated customer-facing tracking experience** — the current `/tracking/[token]` page is a single-shipment, token-based lookup, not a portal; Phase 8 must decide whether to keep issuing per-shipment tokens or build a real customer login that lists all of an account's shipments.
3. **A richer public milestone vocabulary**, if Phase 8 ever needs more granular customer-visible states than the current 5 customer-visible codes registered in the fixtures (`picked_up`/`departed_origin`/`in_transit`/`out_for_delivery`/`delivered`) — new codes are added via `app.register_milestone_code` (Supreme-only, idempotent, platform-wide), never a Phase-8-local enum.
4. **Real client-key generation** — no session/device-fingerprinting mechanism exists yet in this repository; Phase 8 must design a real, stable, non-spoofable `client_key` source for the rate limiter to be effective in production.

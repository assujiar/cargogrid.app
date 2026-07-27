# Phase 2 → Phase 3 Job Order Handoff Contract

**Produced by:** `CG-S7-COM-023` (Prompt 164 — Commercial Documentation and Handoff), per Prompt 164 §20 task 3: "Create Phase 3 Job Order handoff contract examples, compatibility notes and unresolved dependency list."
**Source of truth:** `supabase/migrations/20260724340000_create_commercial_job_order_lineage.sql` (`COM-160`) and `server/contracts/job-order-lineage/job-order-lineage.ts`. This document explains and exemplifies that contract; it does not redefine it — if this document and the migration/contract file ever disagree, the migration/contract file is authoritative.

## 1. What this contract is, and is not

Commercial's own scope ends at producing **one immutable snapshot** per accepted-and-converted quotation — `app.job_order_handoffs.payload`, shaped as `JobOrderDraftInput`. **No Job Order table, route, editor, or domain logic exists anywhere in this repository** (`COM-160` §12/§24's own explicit forbidden scope, re-confirmed unchanged through `COM-163`). Phase 3 (Operations) owns designing and building the actual Job Order domain that *consumes* this snapshot — this contract is Phase 3's own starting input, not a preview of Phase 3's own schema.

## 2. How the payload is produced (API surface)

| Function | Signature | Gate | Behavior |
|---|---|---|---|
| `app.prepare_job_order_handoff` | `(p_quotation_id uuid, p_actor_auth_user_id uuid, p_actor_label text) returns app.job_order_handoffs` | `COM:Edit` | Synchronous, deterministic (no queued job). Re-validates every precondition fresh on every call (quotation `submitted`→`accepted`, converted to an account). Idempotent on `(tenant_id, quotation_id, purpose)` — a retry after the row exists returns it unchanged, never re-derived or duplicated. Masks its own returned `payload`/`payload_hash` per-caller (`COM:View selling price`) directly in the function body, independent of the directory view below. |
| `app.job_order_handoffs_directory` | view | RLS + `COM:View selling price` masking | The read path every later query should use — `payload`/`payload_hash` nulled out (`payload_masked=true`) for any caller lacking `COM:View selling price`, mirroring `app.quotations_directory`'s own masking shape. |

Both are `authenticated`-granted (tenant-scoped, RLS/RBAC-gated) and `service_role`-granted (for a future Phase 3 worker/integration to read via the service-role client, the same two-client pattern every Commercial capability uses).

## 3. The `JobOrderDraftInput` schema (field-by-field)

```typescript
// server/contracts/job-order-lineage/job-order-lineage.ts
{
  schemaVersion: number;          // currently 1 — bump on any breaking shape change, never reinterpret silently
  source: {
    quotationId: string;          // uuid — the exact quotation version accepted
    quoteNumber: string;          // e.g. "QTN-2026-000042"
    versionNumber: number;        // the quotation's own version (COM-152)
    opportunityId: string;        // uuid
    prospectId: string;           // uuid
    accountConversionId: string;  // uuid — app.account_conversions.id (COM-155)
  };
  customer: {
    accountId: string;                    // uuid — app.accounts.id, the canonical FK (COM-161)
    customerSnapshot: Record<string, unknown>; // the exact identity/contact/address the customer accepted (app.quotations.customer_snapshot, pinned — never re-read live from app.accounts)
    contactId: string | null;
    contactName: string | null;
    contactEmail: string | null;
    contactPhone: string | null;
  };
  cargoService: Record<string, unknown>;  // app.opportunities.requirements snapshot (service type, cargo description, lanes, target ready date, etc.)
  pricing: {
    currency: string;             // ISO 4217, e.g. "IDR"
    subtotalAmount: number;
    discountAmount: number;
    taxAmount: number;
    totalAmount: number;
    lines: Record<string, unknown>[];  // app.quotation_lines snapshot, one entry per line
  };
  contract: {                     // null if the account has no published contract
    customerContractId: string;
    rootContractId: string;
    versionNumber: number;
    status: string;
  } | null;
  credit: {                       // null if no credit check was ever run for this account
    outcome: string;              // e.g. "allowed" | "blocked_hold" | "blocked_no_profile" | "blocked_over_limit"
    checkedAt: string;            // ISO 8601 timestamp
    // deliberately no dollar limit field -- app.check_customer_credit (COM-157) exposes
    // only outcome/checkedAt to this payload, by design (sidesteps fine-grained masking
    // inside the credit section entirely)
  } | null;
  acceptance: {
    decidedByName: string;        // the customer's own typed name at accept/reject time
    decidedAt: string;            // ISO 8601 timestamp
    decision: string;             // "accepted" (the only decision that can reach this payload)
  };
}
```

## 4. Full synthetic example (redacted/fictional — no real customer data)

```json
{
  "schemaVersion": 1,
  "source": {
    "quotationId": "8f14e45f-ceea-467e-adcc-fa3bbbb0a3d1",
    "quoteNumber": "QTN-2026-000042",
    "versionNumber": 1,
    "opportunityId": "a1b2c3d4-e5f6-4789-9abc-def012345678",
    "prospectId": "11111111-2222-3333-4444-555555555555",
    "accountConversionId": "66666666-7777-8888-9999-aaaaaaaaaaaa"
  },
  "customer": {
    "accountId": "bbbbbbbb-cccc-dddd-eeee-ffffffffffff",
    "customerSnapshot": {
      "legal_name": "Contoso Freight Indonesia PT",
      "trade_name": "Contoso Freight",
      "tax_id": "01.234.567.8-901.000",
      "billing_address": { "line1": "Jl. Sudirman 1", "city": "Jakarta", "country": "ID" }
    },
    "contactId": "cccccccc-dddd-eeee-ffff-000000000000",
    "contactName": "Jane Doe",
    "contactEmail": "jane.doe@contoso-freight.example",
    "contactPhone": "+62-811-0000-0000"
  },
  "cargoService": {
    "service_type": "ocean_freight",
    "mode": "FCL",
    "cargo_description": "General cargo, non-hazardous",
    "origin": "Jakarta",
    "destination": "Surabaya",
    "target_ready_date": "2026-08-15"
  },
  "pricing": {
    "currency": "IDR",
    "subtotalAmount": 15000000,
    "discountAmount": 0,
    "taxAmount": 0,
    "totalAmount": 15000000,
    "lines": [
      {
        "line_type": "service",
        "description": "Ocean freight, Jakarta → Surabaya, 1x20ft FCL",
        "quantity": 1,
        "unit_amount": 15000000,
        "line_total": 15000000
      }
    ]
  },
  "contract": null,
  "credit": {
    "outcome": "blocked_no_profile",
    "checkedAt": "2026-07-27T03:15:00.000Z"
  },
  "acceptance": {
    "decidedByName": "Jane Doe",
    "decidedAt": "2026-07-27T02:50:00.000Z",
    "decision": "accepted"
  }
}
```

A caller lacking `COM:View selling price` receives the same row shape with `payloadMasked: true` and `payload: null`/`payloadHash: null` — never a partially-redacted payload, always wholesale null, matching `app.quotations_directory`'s own masking convention.

## 5. Compatibility notes

- **Idempotency key**: `(tenant_id, quotation_id, purpose)`. Phase 3 may safely call `prepare_job_order_handoff` more than once for the same quotation — it will never produce a second row or a different payload for the same purpose.
- **`purpose` column**: `not null default 'job_order_draft'` — every row produced by `app.prepare_job_order_handoff` today uses exactly this value (it is hardcoded in the function body, not caller-supplied). Phase 3 designing a second purpose (e.g. a partial/split Job Order) must first widen `prepare_job_order_handoff` to accept a `p_purpose` parameter — the current function offers no way to request a different one.
- **Schema versioning**: `schemaVersion` is `1` for every row produced through `COM-163`. Any future Commercial change to the payload shape must bump this field — Phase 3 consumers should branch on `schemaVersion`, never assume it is always `1`.
- **`downstreamReference`/`deliveredAt`**: real, structurally-ready columns on `app.job_order_handoffs`, currently always `null` — there is no Phase 3 consumer yet to populate them. Phase 3's own first integration should write a real downstream reference (its own Job Order id or number) back into this column once it creates the corresponding Job Order, and set `deliveredAt`/`status='delivered'` — the exact mechanism (a new RPC, or direct authorized write) is Phase 3's own design decision, not prescribed here.
- **Money precision**: every amount field is a PostgreSQL `numeric` end to end, serialized as a JSON number by `pricing`'s own snapshot — Phase 3 must not round-trip through a binary floating-point type without re-quantizing to the original scale.
- **`contract`/`credit` are independently nullable** — an account may have accepted quotations with no published contract and/or no credit check ever run. Phase 3 must handle both as legitimate absence, not an error.

## 6. Unresolved dependency list (what Phase 3 must still design/build)

1. **The Job Order domain itself** — table(s), status lifecycle, RLS, RBAC actions, UI. Nothing here is inherited from Commercial beyond this one input contract.
2. **A downstream-reference write-back mechanism** — how/when `app.job_order_handoffs.downstream_reference`/`delivered_at`/`status` get populated once a real Job Order exists.
3. **A real worker or integration path to consume `app.job_order_handoffs_directory`** — no live REST/GraphQL route or background worker reads this table anywhere in this repository today; Phase 3 must build the actual consumer (a `service_role`-authenticated job, or an internal Phase 3 API route).
4. **Multi-purpose handoff support**, if Phase 3 ever needs more than one Job Order per accepted quotation (e.g. split shipments) — the current schema supports multiple `purpose` values structurally (the idempotency key includes `purpose`), but no second purpose has ever been produced or tested.
5. **Address/site canonicalization** — `customerSnapshot.billing_address` is a jsonb blob, not a normalized, reusable site master (§6 of `COMMERCIAL_HANDOFF_PACKAGE.md`). If Job Order needs a structured origin/destination site concept beyond the free-text `cargoService.origin`/`destination` strings, Phase 3 must design that itself.

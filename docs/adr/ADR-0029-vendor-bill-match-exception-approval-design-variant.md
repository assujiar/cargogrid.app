# ADR-0029 — Vendor-bill match-exception approval stays a domain-owned maker-checker, not a `PLT-123` routed request

**Status:** `ACCEPTED`
**Date:** 2026-08-31
**Closes:** `ISS-2026-061` (Medium, open since 2026-08-09), by taking the second of the two
outcomes that entry itself named: *"either migrate match-exception approval onto the canonical
engine or to formally, explicitly disclose the divergence as an accepted design variant."*
**Related:** `ISS-2026-069` (the `PLT-121` approval-config singleton — the load-bearing fact
below), `PRC-259` (procurement approval on-ramp), `PRC-265` (vendor invoice matching).

---

## The question

`259_PROCUREMENT_APPROVAL_PROMPT.md` line 91 names seven entity types the canonical Platform
Approval Engine (`PLT-123`: `app.approval_requests` / `app.request_approval` /
`app.decide_approval_step`) must govern: *activation / rate / selection / PO / contract / match /
exception*.

Six of them route canonically, through `app._request_procurement_entity_approval`
(`20260730660000:444`). The seventh — **match** — does not.
`app.request_vendor_bill_match_exception_approval` and
`app.decide_vendor_bill_match_exception_approval` (`20260730750000:1739,1786`) are a separate,
domain-owned maker-checker with zero reference to the canonical engine.

`ISS-2026-061` was right that this is a real divergence and right that it was undisclosed. The
question this ADR answers is which way to resolve it.

## What was actually verified, not assumed

Everything below was read directly this checkpoint, not carried forward.

**1. The engine itself does not impose the seven-value limit.**
`app.approval_requests.entity_type` is `text not null default 'generic'`
(`20260719090000:180`) — free text, polymorphic, application-validated. The six-value CHECK the
issue cites lives on `app.procurement_approval_policies.entity_type`
(`20260730660000:189`), which is `PRC-259`'s **threshold-policy** table, not the engine. So the
schema obstacle the issue implies does not exist. Migrating is mechanically easy. That is
precisely why the decision has to rest on consequences instead.

**2. The canonical on-ramp makes approval CONDITIONAL. The current path makes it ABSOLUTE.**
This is the fact that decides the ruling.

`app.evaluate_procurement_approval_requirement` (`20260730660000:380`) looks up a **published**
policy for `(tenant, entity_type)` and, finding none, returns `required = false`. Its caller then
short-circuits to `approval_status := 'not_required'` and opens no request at all
(`20260730660000:469`).

Applied to invoice matching, that means: a tenant with no published
`vendor_bill_match_exception` policy would have its match exceptions clear **with no approval and
no approver**. Today that is impossible — `app.decide_vendor_bill_match_exception_approval` is the
only route from `overall_status = 'exception'` to `matched`, and it always requires a distinct,
`PRC:Approve`-holding second person.

So "migrate onto the canonical engine" is not a neutral consistency change. On this particular
path it converts an unconditional financial control into a tenant-configurable one whose default,
in an unconfigured tenant, is **off**. A control that disappears when nobody configured it is not
a stronger control.

**3. Migrating would also make the path fail closed for unconfigured tenants.**
When a policy *does* require approval, `app._request_procurement_entity_approval` resolves the
tenant's published routing definition and raises `approval_definition_not_configured` if there is
none (`20260730660000:482`). This is not theoretical: `commercial-hardening.sql:157` and
`commercial-quotation-approval.sql:194` both prove that failure live in the Commercial domain.
A tenant that has not yet published an approval routing definition would go from "can clear match
exceptions with a second approver" to "cannot clear match exceptions at all" — a launch-day
regression on an accounts-payable path.

**4. And it would add a fifth consumer to a singleton already flagged as overloaded.**
`ISS-2026-069` (open, Medium) establishes by direct read that `app.config_objects` permits **at
most one** published `'approval'` config object per tenant at `scope_level = 'tenant'`, and that
`app.request_approval`'s `entity_type` argument "is stored purely for record-keeping on the
resulting request row and is never used to select or filter which routing definition applies."

Four domains already share that one definition: Sales quotation approval, commercial credit
control, procurement PO approval, and HR job offers. Routing vendor-bill match exceptions through
it would make them the fifth — meaning the approver chain a tenant designs for HR job offers would
govern their accounts-payable variance approvals, and vice versa. That is not the governance the
prompt's word "govern" was asking for. It is the opposite.

`ISS-2026-069` is explicitly owned by "a future Platform/Approval-Engine hardening prompt with a
mandate spanning every `PLT-121` consumer" and needs its own ADR. Widening its blast radius in
order to close a consistency finding would be trading a real problem for a cosmetic one.

**5. The domain path carries a guarantee the engine has no equivalent of.**
`app.decide_vendor_bill_match_exception_approval` re-verifies **at the point of commitment** that
the case is still genuinely in `exception` and that the underlying `app.finance_vendor_bills` row
is still not `void` (taxonomy C-15, `20260730750000:1835,1841`). `app.decide_approval_step` knows
nothing about match cases or vendor bills and cannot. `PRC-259`'s own canonical wrappers sync
their source entity *after* the engine decides; they do not gate the decision on the source still
being live. Migrating would therefore require re-implementing this guarantee in a wrapper anyway —
so the canonical engine is not even a superset of what exists.

## Decision

**The vendor-bill match-exception approval remains a domain-owned maker-checker. The divergence
from `259_PROCUREMENT_APPROVAL_PROMPT.md` line 91 is accepted, explicitly, as a design variant.**

It is accepted on the evidence above, not on convenience: on this path the canonical engine would
make an unconditional control conditional, introduce a new unavailability failure, and enlarge a
known architectural defect — while not subsuming the commitment-time guarantee the domain path
already has.

## What is genuinely given up, stated plainly

An accepted variant is only honest if its cost is named. Compared with a `PLT-123`-routed request,
this path has:

- **No unified approver inbox.** `app.list_pending_approval_steps_for_actor` (`20260719090000:845`)
  will not show a pending match exception. An approver has to look at the invoice-matching surface
  specifically. This is the real operational cost, and the most likely one to be felt.
- **No delegation.** `app.approval_delegations` cannot cover an approver on leave here.
- **No escalation.** `app.escalate_approval_step` has no counterpart; a stalled exception stalls.
- **No multi-step or threshold patterns.** One approver decides, always. (Note this is *stricter*
  than a misconfigured canonical chain, not weaker — but it is also not configurable upward.)
- **No MFA step-up parameter.** Already disclosed at `docs/build-log/phase-06/PRC-265.md` §5
  item 11; this ADR does not change that disposition, it records it in one place with the rest.

What is **not** given up, and is pinned by test: the approval is mandatory for every exception,
self-approval is blocked (C-18), the decision re-verifies the case and the bill at commitment
(C-15), and every request and decision is captured in `app.audit_logs` and the domain's own event
stream.

## The condition for revisiting

This ruling is **conditional, not permanent**. It should be reopened when — and only when —
`ISS-2026-069` is resolved such that a tenant can publish a **per-domain** approval routing
definition, and the procurement on-ramp can express "always required, regardless of policy
configuration" without depending on a tenant having published a policy row.

At that point migration becomes strictly additive — the domain path would gain the inbox,
delegation and escalation without giving up unconditionality — and the trade that produced this
ADR no longer holds. Until then, migrating is a net loss of control on an accounts-payable path.

## Evidence and enforcement

The ruling's central claims are **executable**, not prose. `scripts/db-tests/`
`procurement-vendor-invoice-matching.sql` carries a dedicated block proving, live:

- `app.evaluate_procurement_approval_requirement` rejects `vendor_bill_match_exception` outright
  today (`invalid_entity_type`) — so a future half-migration cannot happen silently;
- the same function returns `required = false` for a governed entity type with no published
  policy — the conditionality this ADR refuses to import;
- the domain path is genuinely unconditional: an exception approval is requested and required in a
  tenant that has **no** procurement approval policy and **no** published approval routing
  definition at all, where the canonical on-ramp would have returned `not_required`;
- neither `app.vendor_bill_match_exception_approvals` nor `app.vendor_bill_match_cases` carries a
  foreign key into `app.approval_requests` — pinning that the two mechanisms stay distinct rather
  than drifting into a half-bound hybrid, which would be worse than either.

If a future change migrates this path onto the engine, those assertions fail and this ADR has to
be revisited deliberately — which is the point.

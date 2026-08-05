# Supabase Realtime outage (Phase 5 tracking consumers) — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** Support, DevOps/on-call, developers evaluating whether to add a Realtime dependency to a Phase 5 consumer in the future
**Status:** `ACTIVE`
**Owner:** DevOps
**Since:** Phase 5 (`ATW-226H`, Fleet Control Tower)
**Severity class:** `N/A` — this runbook exists to record, honestly, that its own named incident class **does not currently apply to this repository**, rather than silently omitting the topic the governing prompt names.

> This document intentionally does not describe a Realtime outage procedure, because Phase 5 has no live Supabase Realtime dependency to fail. Read §1 before assuming this is a stub or an oversight.

## 0. Why this runbook exists in this shape

`docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/247_ADVANCED_TMS_WMS_DOCUMENTATION_HANDOFF_PROMPT.md` §20 and `docs/ai-agent-build-prompt-package/10-phase-05-advanced-tms-wms/219_ADVANCED_TMS_WMS_README.md` §6 both name Realtime as an in-scope operational concern — the planning document's own cross-cutting controls state "Realtime is limited to authorized active trips/vehicles," and Prompt 247 §20 lists "gateway, Supabase, mobile, provider, Realtime and network outage runbooks" as a required deliverable set. This runbook is that required deliverable, written to match what is **actually implemented**, not what the planning language assumed would be built by this point — per this same checkpoint's own instruction to describe verified behavior only, never invented behavior.

## 1. Symptom / trigger

**None exists to trigger.** Direct inspection of the actual Fleet Control Tower and every other Phase 5 tracking consumer confirms zero Supabase Realtime usage anywhere in this repository:

- A repository-wide search for `supabase.channel(`, `.realtime(`, `createRealtimeClient`, and `from(...).on(` (the Supabase JS Realtime subscription patterns) across `app/` and `server/` returns **zero matches**.
- `docs/build-log/phase-05/ATW-226I.md` §4.1 independently confirmed the same thing during Phase 5's own closing verification: "Realtime is not used anywhere in this family (grep-confirmed zero `supabase.channel`/`.realtime` usage across `app/`/`server/`)."
- The Fleet Control Tower (`app/(tenant)/[tenantSlug]/operations/fleet-control-tower/page.tsx`, `ATW-226H`) is an ordinary Next.js **Server Component**: it calls `getTenantVehicleTrackingOverview`/`getTenantPendingMilestoneCandidates`/`getTenantPendingExceptionSignals` once, server-side, on each page load/navigation. There is no client-side subscription, no `setInterval`-driven polling loop, and no live-push mechanism of any kind wired into this page as of this checkpoint — a dispatcher sees a fresh snapshot on each page load or manual browser refresh, and nothing pushes an update to an already-open tab.
- The same is true of every other tracking-adjacent read surface in this repository (the `operations/fleet` device/SIM/provider-mapping workspace, the customer-safe public tracking page) — all are request-time server-side data fetches, not live subscriptions.

## 2. Impact

**Not applicable.** There is no live-push mechanism to lose, so there is no "Realtime outage" degraded state to define, diagnose, or recover from. The actual, real staleness behavior a user experiences today is: **the Fleet Control Tower and every other tracking view show data as of the moment the page was last loaded or navigated to; nothing updates automatically while the page sits open.** This is a real, disclosed characteristic of the current implementation, not a failure mode — refreshing the page (or navigating away and back) is how a user gets a newer snapshot, exactly as it would for any ordinary server-rendered page with no live-update feature.

Do not confuse this with the genuine outage modes covered elsewhere: `docs/runbooks/gps-gateway-outage.md` and `docs/runbooks/third-party-provider-outage.md` cover a telemetry *source* going down (which the RPCs this page calls will honestly reflect as stale/degraded source health once the underlying tables reflect it); this runbook covers only whether a *live-push transport layer* exists to fail, and the honest answer is that none does.

## 3. Diagnosis steps

If a future developer or operator suspects a "Realtime" problem with a Phase 5 tracking view, the correct first diagnostic step is to confirm whether the symptom is actually:

1. **Ordinary page staleness** (the expected, current behavior, §2) — resolved by reloading the page, not by investigating a Realtime channel that does not exist.
2. **A genuine data problem upstream** — check `docs/runbooks/gps-gateway-outage.md`, `docs/runbooks/gps-ingestion-database-outage.md`, `docs/runbooks/third-party-provider-outage.md`, or `docs/runbooks/driver-mobile-outage.md` depending on the source in question; the fix belongs to one of those runbooks, not this one.
3. **A genuine Supabase-platform-level Realtime service outage** — this would have zero observable effect on any current Phase 5 consumer, precisely because none of them depend on it. If Realtime is ever added to a future Phase 5 consumer, this runbook's own §0 disclosure becomes stale and must be rewritten to describe the real subscription(s) added, their own channel names, and their own actual degraded-state behavior — not filled in speculatively ahead of that work.

## 4. Resolution steps

Not applicable — there is no Realtime-specific failure to resolve. If the actual symptom is data staleness on a live-page-load basis, no resolution exists beyond what is already true by design (reload the page); if the actual symptom is a telemetry source being unhealthy, follow the relevant source-specific runbook (§3 point 2).

**Rollback procedure if resolution fails:** not applicable for the same reason.

## 5. Communication

Not applicable today. If a future capability adds a real Realtime dependency to a Phase 5 consumer, this section must be rewritten with a real communication plan for that specific dependency at that time — this runbook does not pre-write one for a mechanism that does not exist, since doing so would risk describing a channel/topic/degraded-state shape that the real future implementation might not match.

## 6. Post-incident

Not applicable. If this runbook is ever invoked in a real incident review and the finding was "there was never a Realtime dependency to begin with," that confirms this document is doing its job — recording the honest current architecture rather than a plausible-sounding but fictitious one.

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| 2026-08-05 | Verification (direct code inspection, not a rehearsal of an incident that cannot occur) | Confirmed zero `supabase.channel`/`.realtime`/`createRealtimeClient`/Realtime-subscription usage anywhere in `app/` or `server/`; confirmed the Fleet Control Tower and every other Phase 5 tracking read surface is a request-time server-side data fetch with no live-push mechanism | Repository-wide grep (this checkpoint, `CG-S10-ATW-028`); independently corroborated by `docs/build-log/phase-05/ATW-226I.md` §4.1's own identical prior finding |

No incident rehearsal is possible or meaningful for a mechanism that does not exist. This table will gain a real rehearsal entry only once a real Realtime dependency is added to some future Phase 5 consumer.

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-05 | 0.1.0 | Initial — instantiated at `CG-S10-ATW-028` (Prompt 247), documenting the honest absence of a Realtime dependency rather than a hypothetical outage mode | Claude Code (runtime build agent) |

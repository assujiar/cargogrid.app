# Hypercare — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001`
**Template version:** `0.1.0` (established `CG-S5-PH0-013`, Prompt 92)
**Audience:** Support, DevOps/on-call — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps/SRE (Infrastructure-escalation tier) jointly with Support (L1/L2), per `docs/runbooks/on-call-ownership.md` §5 — no separate hypercare-specific ownership scheme is invented here
**Since:** Step 16 (`CG-S16-RGL-018`, Prompt 408, Hypercare)
**Severity class:** Time-bounded, intensified monitoring following a production release — not itself a severity level; individual incidents found during a hypercare window are classified per `on-call-ownership.md` §5's own P1-P4 model

> A runbook describes a real, previously-observed or deliberately-rehearsed operational scenario.
> **This one is deliberately honest about what this checkpoint could and could not do**: it ran a
> real, evidence-gathering hypercare *check* against live production (§3), but a genuine hypercare
> *period* — the sustained, multi-day intensified-monitoring window Blueprint §25.2's own
> deployment flow names ("...Production Deploy → Production Smoke Test → **Monitoring &
> Hypercare**") — requires calendar time and staffed humans this single checkpoint does not have.
> Marked `NOT_YET_STAFFED` in §5, not fabricated as run.

## 0. Why this file exists

`docs/build-log/release-go-live/00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §12 named "Hypercare /
go-live support" as **does not exist** and assigned `RGL-408` as its producing lane. §11.4 already
seeded a plan skeleton (required elements: incident intake path, support tier/routing model,
monitoring and alert destinations, adoption tracking, known-issue publication, escalation ladder
with named humans, RCA process, customer communication) and disclosed up front: "the monitoring
half is `PARTIAL` (`HDN-BLK-027`/`028`), and every 'named human' slot is empty." This file is that
runbook, built against that skeleton, reusing `docs/runbooks/on-call-ownership.md`'s own already-
real support-tier/RCA/escalation model rather than re-authoring a parallel one (this repository's
own "one procedure, not two independently-authored ones" discipline — `11_*.md` §4.4's own
precedent, applied here to the support model instead of the rollback model).

**Scope boundary**: `on-call-ownership.md` documents the *steady-state* alerting/on-call model
(what wires to a real incident today, who owns which tier, day to day). This file documents the
*hypercare period* specifically — the intensified attention immediately following a release, when
a regression is most likely and most costly to miss — and points back to `on-call-ownership.md`
for everything that does not change between "hypercare" and "steady state."

## 1. Symptom / trigger

Hypercare begins the moment a release candidate reaches Production (`RGL-405`, `RGL-404.md` §12A —
2026-08-27, commit `c11c616`, then advanced through 8 further Track B batch merges through
`c77d479`/`ffa57ac`) and continues through an intensified-monitoring window before returning to
steady-state on-call. Trigger for escalating out of hypercare into an ordinary incident: any
signal in `on-call-ownership.md` §3 (a wired alert) or §4 (a failure class not yet wired, requiring
manual `app.audit_logs`/runtime-log discovery) firing during the window.

## 2. Impact

Same P1-P4 classification `on-call-ownership.md` §5 already uses — hypercare does not invent a
separate severity scale. What differs during hypercare is response posture, not classification:
every signal gets checked proactively rather than waiting for a report, and the response window
tightens informally even for signals that would otherwise sit at P3/P4.

## 3. Diagnosis — hypercare check performed this checkpoint, live evidence

Real, live evidence gathered against the current release candidate (`main` HEAD `ffa57ac`,
Vercel production deployment built from that commit, `state: READY`) rather than assumed clean:

**Runtime error telemetry, 7-day window** (`mcp__Vercel__get_runtime_errors`, `since: 7d`): **5
error groups found, all historical.** Every group's own `last=` timestamp is `2026-08-25T09:08` or
earlier — before the Track A production fix (`RGL-404.md` §12A) that resolved the two previously-
live High-severity defects (`RGL-BLK-007`/`ISS-2026-295`, `RGL-BLK-008`/`ISS-2026-296`), and before
every one of the 8 Track B batches deployed. Named groups: `ApiLogMutationError` (`api_logs_actor_
shape_check` violation, 7 occurrences, 2026-08-25 08:48-09:08), a `ZodError` on a malformed
webhook `connectionId` (2 occurrences, same window — the exact shape `ISS-2026-296` already fixed),
`SUPABASE_SERVICE_ROLE_KEY is not set` (1 occurrence, 2026-08-25 02:22, tied to a stale
deployment id `dpl_4vgM6mR6Y5xpA3UfGxsdY2WFCs4U` predating the current one), `Could not find the
function public.record_api_request(...)` (1 occurrence, 2026-08-25 03:18 — a schema-cache/
function-signature mismatch on an old deployment, self-resolving once that deployment was
superseded), and `NEXT_PUBLIC_SUPABASE_ANON_KEY is not set` (1 occurrence, first seen 2026-08-19,
last seen 2026-08-25). **Zero occurrences of any of these, or any new error, since 2026-08-25
09:08** — independently re-confirmed against the narrower trailing-24h window at `RGL-407`
(2026-08-28, zero errors) and again at this checkpoint's own 7-day pull. No new incident this
hypercare window.

**Live health probes**, direct against `https://cargogrid-app.vercel.app` (re-confirmed, same 3
checks as `RGL-407`): `/api/health` `200`; `/api/ready` `200 {"status":"ok"}`; `/api/v1/status`
(no Bearer key) clean `401`, structured error, no raw stack trace. All green.

**Live Supabase security-advisor sweep**: unchanged from `RGL-407`'s own pull earlier the same
day — 1 pre-existing `ERROR` (`spatial_ref_sys`, already accepted), no new `ERROR`.

**Known-issue publication**: `docs/runtime/KNOWN_ISSUES.md` is the real, currently-accurate,
continuously-maintained publication of every open item (102 remaining: 0 Critical, 6 High, 52
Medium, 44 Low, per Track B Batch 8's own close-out) — this **is** the "known-issue publication"
element §11.4's own skeleton named, not a separate customer-facing document (none exists — see
§6).

**Adoption tracking**: **none exists, honestly disclosed, not fabricated.** The live hosted
project is genuinely empty of tenant data — re-confirmed at `ISS-2026-294`'s own re-verification
(`select count(*) from auth.users` = 1, a synthetic non-tenant row; every tenant-scoped table
queried returns 0 rows). There is no real tenant to track adoption for yet; this is the expected,
correct pre-launch state, not a gap this checkpoint could close by building a dashboard for zero
users.

## 4. Resolution steps

No active incident was found (§3) — no resolution steps were required this checkpoint. If a
signal had fired: follow `on-call-ownership.md` §4's own resolution steps exactly (query the
wired-alert path first, fall back to `app.audit_logs`/domain-specific records for an unwired
failure class, escalate manually per §5's tier table since no automated dispatch exists).

## 5. Communication and escalation — the honest gap

**No automated communication or escalation-dispatch mechanism exists** (`on-call-ownership.md` §6,
`ISS-2026-251`, `OPEN`, unchanged) — an unacknowledged incident during hypercare relies on the
same manual discovery/notification path as steady-state on-call.

**Every "named human" slot in the escalation ladder is empty.** `on-call-ownership.md` §5's own
support-tier table (L0-L3, Security escalation, Infrastructure escalation) names *roles*, not
people — this repository has never had a staffed on-call rotation, a named Incident Commander, a
named Security Lead, or a named DevOps/SRE on-call engineer, at any checkpoint through this entire
build. `00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §11.3 already disclosed this identically for the
communication plan ("Business acceptors — none exist," "End users/tenants — none exist and no
channel is defined"). **This is a genuine, human-only, Track-C-class gap this session cannot
close** — no tool available to this agent can hire, assign, or roster a real person into an
on-call rotation. Marked `NOT_YET_STAFFED` here rather than fabricated as staffed.

**Customer communication**: no channel exists (§11.3, unchanged) — there is no real tenant to
communicate with yet (§3's own adoption-tracking finding), so this is consistent with, not
independent of, the pre-launch state rather than a separately-late gap.

## 6. Post-incident

No incident occurred this checkpoint, so no RCA was required. The RCA process itself is real and
ready: `on-call-ownership.md` §5's own binding requirement (mandatory for P1, security incident,
tenant-isolation failure, financial posting/data corruption, production rollback, repeated P2,
major data-migration failure), using the same 12-field incident record Blueprint §30.4 specifies.
Nothing new is invented here.

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| 2026-08-28 | Real, live hypercare check (point-in-time, not a sustained multi-day window) | No active incident found; 5 historical error groups confirmed resolved and non-recurring since 2026-08-25; all 3 health probes green; security-advisor sweep unchanged; adoption tracking confirmed correctly empty (no tenant onboarded yet) | `docs/build-log/release-go-live/RGL-408.md` |

**A genuine, sustained, multi-day hypercare monitoring period, staffed by a real on-call rotation,
has never been run against this project** — this checkpoint's own point-in-time check is real
evidence for the moment it was taken, not a substitute for the sustained window Blueprint §25.2's
own deployment flow names. Marked `NOT_YET_STAFFED`, not fabricated as complete, per this
template's own header discipline (the same honesty standard `deployment-rollback.md` §7 applied
to rollback rehearsal, applied here to hypercare staffing).

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-28 | `0.1.0` | Initial — authored at `RGL-408` (Prompt 408, Hypercare), closing the "Hypercare / go-live support" row `00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §12 named as not yet existing. | Claude Code |

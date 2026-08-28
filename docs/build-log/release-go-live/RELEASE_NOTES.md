# Release `RC-2026.08.25-1` — 2026-08-28

**Template:** `docs/templates/RELEASE_NOTES_TEMPLATE.md` (`CG-DOCS-RELEASE-001`, `0.1.0`)
**Authored at:** `RGL-411` (Prompt 411, `CG-S16-RGL-021`, Release Go-Live Documentation Handoff), 2026-08-28.
**Status:** `ACTIVE`
**Owner:** Release Manager (this session, no separate human role exists)
**Phase:** Step 16 — Release Candidate and Go-Live

> Every item below traces to a `VERIFIED` task/build log or a merged, gate-passing PR — never a
> planned/in-progress item. **This is not a production, pilot, GA, or market-ready claim.** That
> determination belongs to `RGL-412` alone, per `00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §13.

---

## 1. Summary

`RC-2026.08.25-1`, frozen at `RGL-392` (2026-08-25) and amended 30 times since as Step 16's own
checkpoints found and fixed real defects, is the release candidate this Step 16 range (Prompts
391-412) has verified, deployed to production, and reviewed. Production first went live under a
recorded go decision at `RGL-405` (2026-08-27, `RGL-404.md` §12A addendum) and has since advanced
through 8 further Track B backlog-remediation batches plus 4 further Step 16 checkpoints
(`RGL-407`-`410`), each independently verified. No new product feature shipped anywhere in this
range — Step 16's own No-New-Feature Rule (`RGL-393`) forbids it.

## 2. New features

None. This range freezes, verifies, deploys, supports, and reviews a candidate already built by
Phases 0-9 and hardened by Step 15 (`FULL_SYSTEM_HARDENING_VERIFIED`, `HDN-389`) — it does not add
capability.

## 3. Changes

| Change | Impact | Evidence |
|---|---|---|
| Production deployment established | The release candidate is live at `cargogrid-app.vercel.app`, gated only by the operator's own explicit `GO_DECIDED` override (`RGL-BLK-001` remains architecturally unfixed — see §8) | `RGL-404.md` §12A, `RGL-405`/`RGL-406` |
| 2 runbooks newly authored | `docs/runbooks/deployment-rollback.md`, `docs/runbooks/hypercare.md` — closing real, previously-disclosed documentation gaps | `RGL-407`, `RGL-408` |
| 8 Track B backlog-remediation batches | Historical `KNOWN_ISSUES.md` backlog reduced from 147 to 102 tracked items, each with a `RESOLVED` paragraph or an explicit owner-named disposition | `docs/build-log/release-go-live/BACKLOG_INVENTORY.md` |
| Raw-mutation tripwire | New `public.list_untracked_table_mutations()` observability RPC, closing a real detection gap on unwrapped table mutations | Batch 8, `RGL-404.md` §12 items 74-99 |

## 4. Fixes

| Fix | Related issue | Evidence |
|---|---|---|
| Every `app/api/v1/**` route now returns a clean `401` for an invalid Bearer key instead of an uncaught `500` | `RGL-BLK-007` | `RGL-401`, deployed and live-confirmed at `RGL-406`, re-confirmed unchanged through `RGL-410` |
| Webhook ingestion routes no longer crash on a malformed `connectionId` | `RGL-BLK-008` | `RGL-401`, deployed and live-confirmed at `RGL-406` |
| Live production Finance-write outage found and fixed same checkpoint | `RGL-BLK-006` | `RGL-404` |
| ~45 further defects across the historical backlog (RLS/grants, RBAC defense-in-depth, HRIS/customer-portal/loyalty scope gaps, accessibility, observability, and others) | see `BACKLOG_INVENTORY.md`'s own per-batch tables | Track B, Batches 1-8 |

## 5. Deprecations / breaking changes

None.

## 6. Known issues carried into this release

Reproduced by reference from `docs/runtime/KNOWN_ISSUES.md` and
`docs/build-log/release-go-live/BACKLOG_INVENTORY.md` (not re-typed): **102 items remaining** as of
Batch 8's close (`RGL-408`) — 0 Critical, 6 High, 52 Medium, 44 Low. Each carries a named owner and
disposition; none is silently dropped. The 6 open High items and their disposition class are listed
in `BACKLOG_INVENTORY.md`'s own High-severity table.

**Standing, disclosed, Track-C (human-only) gaps**, unchanged by this release and not expected to
close from inside an agent session: `RGL-BLK-001` (production auto-deploys from `main` with no
go/no-go gate — GitHub branch-protection or Vercel promotion-gate configuration required); no real
staging tier; no named human UAT acceptor; no licensed external penetration-test engagement; the
hypercare escalation ladder's named-human slots (`NOT_YET_STAFFED`); `ISS-2026-300` (a 9-migration
ledger filename/version drift, `INFRA`-classified, schema itself unaffected).

## 7. Upgrade / migration notes

379 migration files as of this release, applied directly against the hosted Supabase project via
`apply_migration` rather than through a deploy-time migration step (no such step exists in this
repository's Vercel deployment — see `docs/runbooks/deployment-migration-guard.md`). `ISS-2026-300`
(§6 above) discloses a real, open gap in this mechanism: 9 migrations were recorded under their
Supabase wall-clock apply version rather than their repository filename version, which would cause a
future `supabase db push`-style replay to attempt to re-run them. No corrective action was taken
within this checkpoint's own scope (documentation and review only); it is carried forward as a named,
owned item.

## 8. Go/No-Go evidence

`RC-2026.08.25-1` carries a `GO_DECIDED` verdict, reached only after an explicit, separate operator
override of `RGL-BLK-001` (production auto-deploy with no go/no-go gate, architecturally unfixed by
any tool available to this session) and three further tracked gaps (staging tier, UAT acceptor,
external pentest) — see `docs/build-log/release-go-live/GO_NO_GO_REPORT.md`'s own addenda and
`RGL-404.md` §7/§12A for the exact override record. This is a release-proceed decision, not a
production-ready, market-ready, or GA claim — `RGL-412` (Closure Verification) is the only
checkpoint in this range authorized to make that determination, and Step 17 eligibility itself is
explicitly gated on `RGL-BLK-001` per `00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §13 condition 3. Full
current-state readiness evidence: `docs/runtime/RELEASE_READINESS_MATRIX.md` §6 (`RGL-410`).

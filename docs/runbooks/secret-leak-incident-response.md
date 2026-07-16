# Secret leak (accidentally committed credential) — Runbook

**Template ID:** `CG-DOCS-RUNBOOK-001` (instantiated from `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md`)
**Template version:** `0.1.0`
**Audience:** Support, DevOps/on-call — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps / Security
**Since:** Phase 0 (`CG-S5-PH0-015`, Prompt 94)
**Severity class:** Critical if the leaked value is a real, live, unrotated credential; the detection/response procedure itself is real today even though no live credential has ever existed in this repository (`docs/discovery/06_SECURITY_BASELINE.md` §6).

> `NOT_YET_REHEARSED` against a real leak (none has occurred, `docs/discovery/06_SECURITY_BASELINE.md` §11 `SEC-2026-001`) — this runbook is the pre-committed response contract, exercised today only against `scripts/security/check-secrets.ts`'s own real detection capability (§7).

## 1. Symptom / trigger

`pnpm run security:check` (CI or local) reports a `GENERIC_HARDCODED_SECRET_ASSIGNMENT`, `AWS_ACCESS_KEY_ID`, `PRIVATE_KEY_BLOCK`, `STRIPE_LIVE_KEY`, or `JWT_SHAPED_TOKEN` finding (`docs/standards/SECURITY_STANDARDS.md` §3) in a tracked file — or a human notices a credential-shaped value in a diff/PR review that the scanner missed (the scanner's five patterns are deliberately conservative, not exhaustive, §7).

## 2. Impact

Depends entirely on whether the matched value is a **real, live** credential or a synthetic/placeholder one (the scanner cannot tell the difference — it flags the *shape*, a human confirms the *reality*, §3). A real live credential committed to a Git-hosted repository must be treated as compromised the moment it is pushed, regardless of repository visibility (private repos are still cloned/mirrored/cached in ways that cannot be fully audited after the fact) — this is why rotation (§4), not merely deletion, is the mandatory response.

## 3. Diagnosis steps

1. Open the exact `file:line` the scanner reported and read the real surrounding context (the scanner deliberately never prints the matched value itself, `docs/standards/SECURITY_STANDARDS.md` §3 — a human must look at the actual file to confirm).
2. Classify: **(a)** synthetic/placeholder/test-fixture value (safe, no further action beyond confirming it's genuinely inert — e.g. this repository's own scanner test fixtures, built from AWS's own published non-functional documentation example key, never spelled out literally in this document for the same reason `scripts/security/check-secrets.ts` never prints a matched value, §7) — close as a false positive, or **(b)** a real credential — proceed to §4 immediately, do not wait for a convenient time.
3. If real: identify which system the credential grants access to and its current scope (per `docs/standards/SECURITY_STANDARDS.md` §2's least-privilege rule, a properly-scoped credential limits blast radius even mid-incident).

## 4. Resolution steps

1. **Rotate the credential at its source system immediately** (per `docs/architecture/11_DEVOPS_WORKSTREAM.md` §5's rotation-with-overlap-window rule: issue a new value, keep the old one valid only for the minimum overlap needed to update every real consumer, then revoke the old one — never leave the leaked value valid indefinitely "to be safe later").
2. Remove the value from the current file (fix-forward commit) — `git ls-files`/history still contains it at the old commit; treat the value as permanently compromised regardless of whether history is later rewritten (rewriting published Git history is a destructive operation requiring explicit operator authorization per `AGENTS.md`'s Git Safety Protocol — not performed unilaterally by this runbook).
3. Update every real consumer of the credential (per `ADR-0010`, Vercel Environment Variables / Supabase project secrets) to the new value before the old value's overlap window expires.
4. Re-run `pnpm run security:check` to confirm the specific finding is gone.
5. **Rollback procedure if resolution fails:** if rotation itself fails (source system unavailable), escalate to that system's own incident process — this runbook does not invent a workaround for a third-party outage; the leaked value remains compromised until rotation succeeds.

## 5. Communication

Real incident (§2b): notify DevOps/Security lead immediately, regardless of time — a credential leak is never a "wait until morning" item. No customer-facing communication is warranted unless the credential's scope reached tenant data (in which case this escalates beyond this runbook to `AGENTS.md`'s "Stop and escalate when" tenant-isolation criteria). False positive (§2a): no communication needed, just close.

## 6. Post-incident

Record: what the credential was, its scope, how long it was live in the leaked state, confirmation of successful rotation, and whether the scanner's pattern set (§7) should be extended to catch this shape earlier next time — a real incident that the scanner *missed* is itself evidence for extending `docs/standards/SECURITY_STANDARDS.md` §3's pattern table, tracked as a `KNOWN_ISSUES.md` follow-up, not silently absorbed.

## 7. Rehearsal history

| Date | Type (rehearsal/real) | Outcome | Evidence |
|---|---|---|---|
| 2026-07-15 | Rehearsal (scanner self-test against synthetic fixtures, not a live leak) | All 5 pattern kinds correctly detected against known-shape synthetic values (AWS's own public example key, a synthetic PEM header, a synthetic Stripe-shaped key, a synthetic JWT, a synthetic generic assignment); zero false positive against this repository's own real, current tracked files | `scripts/security/check-secrets.test.ts`, 17/17 passing; `scanRepository()` against the real repo: 0 findings |

A real-leak rehearsal (deliberately committing a synthetic-but-realistic credential to a disposable branch and confirming the full detect→rotate→verify cycle) is required before this runbook can be marked fully rehearsed — tracked as a Phase 1 downstream item once a real credential-issuing system exists to rotate against, not claimed complete here.

## 8. Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-07-15 | 0.1.0 | Initial — instantiated from `SUPPORT_RUNBOOK_TEMPLATE.md` at `CG-S5-PH0-015` | Claude Code (runtime build agent) |

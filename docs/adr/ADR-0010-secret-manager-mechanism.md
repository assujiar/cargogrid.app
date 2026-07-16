# ADR-0010 — Secret-manager mechanism

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-025`   Owning phase/task: Phase 0 (`CG-S5-PH0-015`, Prompt 94, Security Baseline Controls)

## Question

`docs/architecture/11_DEVOPS_WORKSTREAM.md` §10 (`ADR-CAND-ARCH-025`) asks: dedicated secret-manager service vs. hosting-platform-native environment variables, for storing/scoping/rotating every server/secret-classified value this repository consumes (`scripts/env/schema.ts`, `ADR-0003`)?

## Options

1. **Hosting-platform-native environment variables (SELECTED): Vercel Environment Variables for application secrets, Supabase project secrets/API settings for database-adjacent credentials.**
   - Trade-off: matches Tech Arch §6's already-ratified Supabase-centric physical architecture and `ADR-0004`'s already-ratified GitHub Actions/Vercel-adjacent CI baseline — zero new vendor relationship, zero new credential surface, and exactly the mechanism `scripts/env/schema.ts`/`scripts/env/validate.ts` (`ADR-0003`, `PH0-86`) already assumes (`public`/`server`/`secret` classification read from `process.env`, no secret-manager SDK call anywhere in that code). Least-privilege environment scoping (Vercel's per-environment variable scoping: Development/Preview/Production; Supabase's per-project isolation, already matching the seven-tier topology `11_*.md` §2 fixes) is native, not bolted on. Rotation-with-overlap-window (Tech Arch §23.7, `11_*.md` §5, restated in `docs/standards/SECURITY_STANDARDS.md` this checkpoint) is an application-level pattern (keep the old value valid for a fixed window while the new one propagates) that works identically regardless of which mechanism stores the values — not a capability a dedicated secret manager would add.
   - Trade-off against: no built-in secret-access audit log as granular as a dedicated product (e.g. per-read audit trail); no automatic rotation scheduling. Accepted at MVP per the candidate's own recommendation — re-evaluated only if an Enterprise tenant contract requires tenant-specific key custody beyond what the platform-native mechanism provides (the candidate's own stated re-evaluation trigger, not invented here).
2. **A dedicated secret-manager service (e.g. AWS Secrets Manager, HashiCorp Vault, Doppler).**
   - Trade-off: adds a third vendor relationship (beyond Vercel + Supabase already ratified) with its own access-control surface, credential-to-fetch-credentials bootstrapping problem, and — critically — no evidenced requirement in any `VERIFIED` architecture document that the platform-native mechanism cannot satisfy at the current, pre-Enterprise-tenant scale. Rejected on the same "avoid an unevidenced second system" reasoning `ADR-0004` already applied to CI/CD platform choice.

## Decision

**Vercel Environment Variables** for application-level secrets (matches `ADR-0004`'s CI/CD baseline and the ratified Vercel hosting target, `AGENTS.md` "Stack baseline") and **Supabase project secrets/API settings** for database/service-role credentials — both native to already-ratified platform choices, zero new vendor. `scripts/env/schema.ts`'s existing `public`/`server`/`secret` classification (`ADR-0003`) is the enforcement mechanism on the application side; this ADR ratifies the storage mechanism those classified values live in, formalizing what was already implicit rather than introducing a new pattern.

## Evidence

- `docs/architecture/11_DEVOPS_WORKSTREAM.md` §5 (secret/key/certificate lifecycle contract) and §10 (`ADR-CAND-ARCH-025`'s exact question/recommendation).
- `scripts/env/schema.ts`/`scripts/env/validate.ts` (`PH0-86`, `ADR-0003`): already reads every secret-classified value from `process.env` with no secret-manager SDK dependency — confirms this ADR ratifies an already-operative pattern, not a new one.
- `AGENTS.md` "Stack baseline": "Vercel baseline and separate Local/Development/Testing/Staging/UAT/Production environments" — the platform this ADR's mechanism is native to.
- No `VERIFIED` architecture document or ratified CPD/RPD evidences an Enterprise-tenant key-custody requirement today (confirmed via grep across `docs/ai-agent-build-prompt-package/00-control/02_CONFIRMED_DECISION_REGISTER.md`) — the candidate's own re-evaluation trigger is not yet met.

## Consequences

- **DB/API/UI:** none — no schema/contract/component created; this ADR fixes where a future secret value is stored, not any code that reads one (already fixed, `ADR-0003`).
- **Security:** no credential exists yet in this repository (confirmed, `docs/discovery/06_SECURITY_BASELINE.md` §6) — this ADR does not create, store, or expose a secret; it fixes the *mechanism* the first real one (Phase 1's `SUPABASE_SERVICE_ROLE_KEY`, etc.) will use. `docs/standards/SECURITY_STANDARDS.md` (this checkpoint) restates the leakage-prevention/rotation rules this mechanism must honor.
- **Performance:** none — reading `process.env` has no meaningful overhead versus any alternative.
- **Migration/rollback:** trivial — no infrastructure exists to migrate away from; adopting a dedicated secret manager later (if the re-evaluation trigger fires) is additive, not a breaking change to `scripts/env/schema.ts`'s existing classification contract.
- **Downstream impact:** Phase 1's first real deployment configures its first `secret`-classified value (per `scripts/env/schema.ts`) directly in Vercel/Supabase's native mechanism — no new secret-manager onboarding step is inserted into the deployment pipeline `11_*.md` §3/§4 already fixes.

## Propagation

Referenced by: `docs/build-log/phase-00/PH0-94.md`; `docs/adr/README.md` §5.2 (marks `ADR-CAND-ARCH-025` `ACCEPTED`) and §6 (index); `docs/standards/SECURITY_STANDARDS.md` (this checkpoint, secret-handling/rotation section built on this ADR). Does not alter any CPD/RPD or any `docs/architecture/**` decision, and does not change `scripts/env/schema.ts`'s existing, already-correct behavior.

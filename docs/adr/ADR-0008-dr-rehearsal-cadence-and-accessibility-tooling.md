# ADR-0008 — DR-rehearsal cadence and automated-accessibility-checker tool

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-023`   Owning phase/task: Phase 0 (`CG-S5-PH0-012`, Prompt 91, Testing Foundation) for both components — see the scope discrepancy note below

## Question

`docs/architecture/10_TESTING_WORKSTREAM.md` §11 (`ADR-CAND-ARCH-023`) asks two questions together: (a) what DR-rehearsal cadence exercises Blueprint §24.5/§26.3's rollback procedures (§7.4), and (b) what automated WCAG checker is wired into the accessibility CI gate (§6/§8.3) — both explicitly scoped "non-blocking — resolve at Phase 0 testing foundation (Prompt 91)."

## Scope discrepancy (disclosed, not silently resolved)

`docs/adr/README.md` §5.2's candidate register (written at `PH0-084`) lists `ADR-CAND-ARCH-023` under the single topic "DR-rehearsal cadence," reassigned to **"Phase 15 (`HDN-384`)," status `BLOCKED` — deferred, non-blocking** — dropping the accessibility-checker half entirely and moving the remaining cadence half nine phases later than the source document. `docs/runtime/HANDOFF.md` §4 and `docs/runtime/TASK_LEDGER.md` row `012` (both current as of `PH0-90`) still describe this candidate at Prompt 91 as "DR-cadence/accessibility-checker tooling," matching `10_*.md` verbatim — the more recent runtime ledgers did not adopt the README's reassignment. Resolution: `docs/architecture/10_TESTING_WORKSTREAM.md` is the ADR candidate's originating source (`docs/adr/README.md` §5's own header states its candidate register was "reconciled from `docs/architecture/01_*.md`–`13_*.md`," i.e. derived from, not independent of, that source); `README.md` §5.2's Phase-15 reassignment for the cadence half is treated as an unintended narrowing introduced during candidate-register transcription, not a deliberate re-scoping decision — no `docs/architecture/**` document, ADR, or `CHANGE_MANIFEST.md` entry records a rationale for moving it. **This ADR resolves both halves at Prompt 91, as `10_*.md` and the current runtime ledgers specify, and corrects `docs/adr/README.md` §5.2's row accordingly (see Propagation).** The correction is a transcription fix, not a re-litigation of an already-decided scope — consistent with `docs/adr/README.md` §1's own rule that an ADR may not "re-derive already-`VERIFIED` architecture," which cuts the other way here: the README's candidate-register row is not itself `VERIFIED` architecture, `10_*.md` is.

## Options

### DR-rehearsal cadence

1. **Quarterly (SELECTED).**
   - Trade-off: `10_*.md` §11's own recommendation, "aligned to Blueprint §24/§26's already-defined rollback procedures, exercised rather than newly designed" — frequent enough to catch environment/procedure drift before a real incident (`10_*.md` §7.4's stated risk of "too rare to catch drift"), infrequent enough not to burden Staging (§7.4's other named risk) once Staging exists to rehearse against.
   - Trade-off against: no rehearsal can actually execute yet — no Staging/backup/restore infrastructure exists (Phase 0, greenfield, confirmed by `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md`). This ADR fixes the cadence policy now, not its first execution; the first actual rehearsal is gated on the DevOps environment prompts that provision Staging (`docs/architecture/11_DEVOPS_WORKSTREAM.md`), tracked as a distinct downstream item, not invented as already having happened.
2. **Monthly.**
   - Trade-off: no evidenced justification for higher frequency than Blueprint §24/§26 implies; would burden a not-yet-provisioned Staging environment more than the identified risk warrants.
3. **Semi-annual/annual.**
   - Trade-off: `10_*.md` §7.4's own stated risk — "so rare it fails to catch drift before a real incident" — applies directly against this option with no offsetting evidence.

### Automated accessibility-checker tool

1. **`@axe-core/playwright` (SELECTED).**
   - Trade-off: axe-core is the industry-standard rules engine `10_*.md` §7.4 names by example ("axe-core-equivalent automated checker"); the `@axe-core/playwright` binding integrates directly with `ADR-0007`'s already-selected Playwright E2E layer with no second browser-automation dependency. Verified current stable via `npm view @axe-core/playwright version dist-tags` this checkpoint: `4.12.1` (`latest`).
   - Trade-off against: axe-core catches programmatically detectable WCAG violations only (contrast, ARIA, semantic structure) — `10_*.md` §7.4's "manual keyboard/screen-reader spot-check per release" remains required alongside it, not replaced by it; this ADR does not claim automated-only WCAG 2.2 AA sufficiency.
2. **Pa11y.**
   - Trade-off: also axe-core-based under the hood in its default configuration, but ships as a separate CLI/Node API requiring its own browser-driver wiring — no advantage over binding axe-core directly into the already-selected Playwright layer.
3. **Lighthouse (accessibility category).**
   - Trade-off: broader scope (performance/SEO/PWA) than this decision needs; its accessibility category is itself axe-core-derived, so selecting it would add a heavier tool to reach the same underlying engine `@axe-core/playwright` provides directly.

## Decision

1. **DR-rehearsal cadence: quarterly**, policy fixed now; first actual execution gated on Staging/backup-restore infrastructure existing (tracked as a Phase 0 DevOps-environment downstream item, not claimed complete here).
2. **Accessibility checker: `@axe-core/playwright@4.12.1`**, wired into the Playwright E2E layer (`ADR-0007`) as the automated half of `10_*.md` §7.4/§8.3's accessibility-test scope; manual keyboard/screen-reader spot-check remains required per release, unchanged.
3. **`docs/adr/README.md` §5.2's `ADR-CAND-ARCH-023` row is corrected** to reflect both components resolved at Prompt 91 (see Propagation) rather than the accessibility-checker half being silently dropped and the cadence half being reassigned to Phase 15 with no recorded rationale.

## Evidence

- `docs/architecture/10_TESTING_WORKSTREAM.md` §7.4 (browser/WCAG/load/DR rehearsal text), §8.3 (accessibility gate cadence), §11 (`ADR-CAND-ARCH-023`'s exact question/recommendation/blocking-state, "resolve at Phase 0 testing foundation (Prompt 91)").
- `docs/adr/README.md` §5.2 (the Phase-15 reassignment being corrected) and §5's own "reconciled from `docs/architecture/01_*.md`–`13_*.md`" sourcing statement.
- `docs/runtime/HANDOFF.md` §4 and `docs/runtime/TASK_LEDGER.md` row `012` (current runtime ledgers, both still citing the combined DR-cadence/accessibility-checker scope at Prompt 91).
- `npm view @axe-core/playwright version dist-tags` (this checkpoint): `4.12.1` latest stable, confirmed current.
- `docs/discovery/04_DATABASE_MIGRATION_BASELINE.md` (confirms no Staging/backup infrastructure exists yet — basis for "cadence decided now, execution gated later" rather than claiming a rehearsal capability that does not exist).

## Consequences

- **DB/API/UI:** none.
- **Security:** the accessibility checker runs against synthetic, inline test content only this checkpoint (`e2e/smoke.spec.ts`) — no real UI, no tenant data, nothing to leak.
- **Performance:** `@axe-core/playwright`'s scan adds bounded, single-page-scoped runtime to the `e2e` CI job; not measured as an SLA (no page corpus exists yet to benchmark against).
- **Migration/rollback:** additive only — removing the DR-cadence line from this ADR or the `@axe-core/playwright` dependency has no effect on any other decided ADR.
- **Downstream impact:** the DevOps environment prompts that provision Staging must record the first real DR-rehearsal execution against this ADR's quarterly cadence (not re-decide the cadence); Phase 1's first real UI component (`components/ui/`, `ADR-0005`/`ADR-0006`) is the first subject the accessibility gate scans against real markup instead of `e2e/smoke.spec.ts`'s synthetic content.

## Propagation

Referenced by: `docs/build-log/phase-00/PH0-91.md`; `docs/adr/README.md` §5.2 (`ADR-CAND-ARCH-023` row corrected — both components marked `ACCEPTED → ADR-0008`, Phase-15 reassignment removed with a note pointing here) and §6 (index); `docs/architecture/10_TESTING_WORKSTREAM.md` §7.4/§11 unchanged (this ADR resolves the candidate it already raised, it does not rewrite the source document); `e2e/smoke.spec.ts` (this checkpoint, proves the axe-core wiring); `.github/workflows/ci.yml` (`e2e` job). Does not alter any CPD/RPD.

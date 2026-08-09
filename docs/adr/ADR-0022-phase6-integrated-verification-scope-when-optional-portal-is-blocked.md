# ADR-0022 — Phase 6 Integrated Verification proceeds over internally-scoped capabilities while the Optional Vendor Portal stays ADR-blocked

Status: ACCEPTED
Date: 2026-08-08   Approver: Runtime build agent (this process), recorded here per `docs/adr/README.md` §3 ("Bounded Phase 0 technical decision with verified runtime evidence... Runtime build agent... ADR reaches `ACCEPTED` in the same checkpoint") — this is a bounded process reconciliation applying an already-ratified product rule (`249_PROCUREMENT_VENDOR_README.md` §5, RPD-scope, no CPD/RPD reopened), not a new product decision
Source candidate: none prior (newly identified literal-text tension, same character as `ADR-0021`'s own out-of-band process reconciliation)   Owning phase/task: Phase 6 (`CG-S11-PRC-017..021`, Prompts 266–270)
Supersedes/Superseded-by: — (does not reopen `ADR-0020` or any prior ADR)

## Question

`docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/267_OPTIONAL_VENDOR_PORTAL_PROMPT.md` §9 requires, as an upstream dependency, "an explicit Platform identity/membership ADR" resolving external vendor identity within the existing four-layer access model without inventing a fifth layer. `249_PROCUREMENT_VENDOR_README.md` §5 states the package-level version of the same rule and explicitly authorizes the consequence: *"If that runtime ownership is unresolved, block the vendor-portal task while internal procurement continues."*

No such Platform membership/portal-surface ADR exists in this repository as of this checkpoint (verified below). `CG-S11-PRC-018` (Prompt 267) is therefore `BLOCKED`, not built — see `docs/build-log/phase-06/PRC-267.md`.

This creates a literal-text tension one level downstream: `268_PROCUREMENT_VENDOR_INTEGRATED_VERIFICATION_PROMPT.md` §9 (Upstream dependencies) reads: *"PRC-251..267 all `VERIFIED`."* A blocked task can never reach `VERIFIED` without the Platform ADR it depends on — an ADR that is a Platform-level decision, outside every Phase 6 prompt's own allowed-files scope and outside this checkpoint's own operator authorization (which named Prompts 266–270, not a new Platform ADR). Read completely literally, §9 would make Prompt 268 — and therefore Prompt 269, Prompt 270, and Phase 6 closure itself (Prompt 271) — permanently unstartable, which contradicts the README's own express guarantee that portal-blocking "never blocks internal Procurement."

The question: **does Prompt 268's Integrated Verification proceed over the 16 internally-scoped, genuinely `VERIFIED` Phase 6 capabilities plus a disclosed, reproducible `BLOCKED` record for the portal, or does the whole phase stall indefinitely behind a cross-phase Platform decision no Phase 6 prompt has the mandate to make?**

## Options (with trade-offs)

1. **Stall Phase 6 entirely until a Platform membership/portal-surface ADR exists.** Literal compliance with Prompt 268 §9's wording. Rejected: directly contradicts `249_*.md` §5's own explicit, binding guarantee that internal Procurement is never blocked by an unresolved portal ADR; would make 16 already-`VERIFIED` capabilities' worth of evidence permanently unusable for no security or correctness reason; no Phase 6 prompt has the allowed-files scope to author a Platform-level ADR, so this option has no exit ramp inside Phase 6 at all.
2. **Silently treat `CG-S11-PRC-018` as satisfied or out of scope for Prompt 268's own evidence matrix.** Rejected: this is exactly the failure mode `BUILD_EXECUTION_PROTOCOL.md` §5.6 and this repository's own disclosure discipline forbid — a genuine gap presented as closed. Prompt 268 §24 also requires "unmapped means fail," which a silent omission would violate by omission rather than an honest fail-with-reason.
3. **Narrow §9's literal "all `VERIFIED`" to "every internally-scoped capability `VERIFIED`, plus every ADR-blocked capability disclosed with reproduction and resume condition, never silently treated as satisfied or as out of scope."** Adopted. Mirrors `CON-015`'s own already-accepted narrowing technique (a capability prompt's literal clause read down to what it can actually mean once a later, ratified process decision changes the ground it was written on) and is fully bounded by the README's own already-ratified rule — no new product decision, no weakening of any security/tenant/financial invariant, no change to what "20 anchors" or "17 capabilities" mean for the 16 that are genuinely buildable now.

## Decision

Prompt 268 (Integrated Verification) proceeds once `CG-S11-PRC-017` (Prompt 266) reaches `VERIFIED`, evaluating its 17-capability × 20-anchor evidence matrix over:
- the 16 internally-scoped Phase 6 capabilities that are genuinely `VERIFIED` (`CG-S11-PRC-002..017`, Prompts 251–266), and
- `CG-S11-PRC-018` (Prompt 267) recorded as `BLOCKED` in the matrix — not `VERIFIED`, not omitted, not silently marked out of scope — with a direct citation to `docs/build-log/phase-06/PRC-267.md`'s reproduction and resume condition.

`PHASE_6_VERIFIED` (settable only by Prompt 271) must carry this same disclosure forward explicitly. It is never a claim that the vendor portal was built or verified.

## Evidence (cited runtime/architecture sources)

- `docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/249_PROCUREMENT_VENDOR_README.md` §5: "If that runtime ownership is unresolved, block the vendor-portal task while internal procurement continues" — the ratified rule this ADR applies, not reopens.
- `docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/267_OPTIONAL_VENDOR_PORTAL_PROMPT.md` §9: literal upstream-dependency text creating the tension.
- `docs/ai-agent-build-prompt-package/11-phase-06-procurement-vendor/268_PROCUREMENT_VENDOR_INTEGRATED_VERIFICATION_PROMPT.md` §9: literal "PRC-251..267 all `VERIFIED`" text this ADR narrows.
- Runtime verification this checkpoint (2026-08-08): `grep -rlE "portal-surface|four-layer|external.*identity.*membership|membership.*ADR" docs/adr` → no matches; `ls docs/adr` → ADR-0001 through ADR-0021 only, none establishing a Platform external-party membership/portal-surface model.
- `docs/build-log/phase-06/PRC-253.md` (Prompt 253, `VERIFIED`) already recorded the identical gap prospectively at its own checkpoint — this ADR confirms it is still open, not a new discovery, and gives it a durable resolution rather than leaving every future checkpoint to re-derive the same narrowing informally.
- `docs/ai-agent-build-prompt-package/00-control/04_CONFLICT_REGISTER.md`'s `CON-015` — the precedent for narrowing a literal capability-prompt clause via a ratified process decision rather than editing the prompt file itself. `04_CONFLICT_REGISTER.md` is a `FORBIDDEN` path for a runtime agent (`docs/git/GIT_STRATEGY.md` §4: "Decision-change protocol only") — this ADR is recorded here, in the permitted `docs/adr/` mechanism, specifically because the register itself cannot be hand-edited by this process; a future decision-change-protocol pass may add a corresponding register row citing this ADR, mirroring how `CON-015` cites `ADR-0021`.

## Consequences (DB/API/UI/security/performance/migration/rollback + downstream impact)

- **DB/API/UI:** none — this ADR changes no schema, service, or UI. It governs verification-evidence scope only.
- **Security:** no isolation, RLS, RBAC, or field-policy invariant is touched or weakened. The portal is not built and grants no access; blocking it is strictly conservative (deny-by-default) with respect to Prompt 267 §16's own binding rule.
- **Performance:** none.
- **Migration:** none — no schema change.
- **Rollback:** trivial — this ADR only interprets an evidence-matrix scope; reverting it means Prompt 268 would (incorrectly) require the missing Platform ADR before starting, i.e. reverting to Option 1 above.
- **Downstream impact:** `CG-S11-PRC-019..022` (Prompts 268–271). Every Phase 6 closure claim from this checkpoint forward must cite this ADR when explaining why `CG-S11-PRC-018` is `BLOCKED` rather than `VERIFIED` inside an otherwise-complete phase evidence matrix. **Reversal condition:** the moment a Platform membership/portal-surface ADR is ratified and Prompt 267 becomes `READY`/buildable, this ADR's scope narrowing for Prompt 268 becomes moot for future phases but remains the correct historical record for this checkpoint's own evidence matrix — it is not retroactively edited (append-only, matching `ADR-0021`'s own supersession discipline).

## Propagation (which WBS/traceability/context records now reference this)

- `docs/build-log/phase-06/PRC-267.md` (this checkpoint)
- `docs/runtime/TASK_LEDGER.md` — `CG-S11-PRC-018` row (this checkpoint)
- `docs/build-log/phase-06/PROCUREMENT_VENDOR_EXECUTION_INDEX.md` — rows `267`/`268` and §3 "Next eligible task" (this checkpoint)
- `docs/build-log/phase-06/PRC-268.md`, when Prompt 268 runs, must cite this ADR explicitly in its own evidence matrix for the `CG-S11-PRC-018` row
- A future decision-change-protocol pass on `docs/ai-agent-build-prompt-package/00-control/04_CONFLICT_REGISTER.md` may add a `CON-016` row citing this ADR, mirroring `CON-015`'s own citation of `ADR-0021` — out of this checkpoint's own authority to perform directly (the register is a `FORBIDDEN` path for a runtime agent)

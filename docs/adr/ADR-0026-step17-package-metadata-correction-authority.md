# ADR-0026 — Step 17 package-metadata correction authority (five register/metadata files, mechanical corrections only)

Status: ACCEPTED
Date: 2026-08-29   Approver: Repository owner / operator (explicit instruction, 2026-08-29, when asked how Step 17 should handle package corrections it finds: **"Register CON-016 and edit"** — formally resolve the conflict in `04_CONFLICT_REGISTER.md` to permit narrow mechanical metadata corrections and apply them in-package), recorded and operationalized by the runtime build agent per `docs/adr/README.md` §3
Source candidate: `ADR-CAND-ARCH-037` (newly minted; no prior candidate covers package-file write authority)   Owning phase/task: Step 17 — Final Package Validation (`CG-S17-FPV-001..017`, Prompts 414–430)
Supersedes/Superseded-by: — (does not reopen any prior ADR; narrows one row of `docs/git/GIT_STRATEGY.md` §4)

## Question

Step 17's own prompts instruct the executing agent to write into the prompt package:

- Prompts 415–429 §20.4 — "Correct package metadata only if the defect is mechanical and
  source-safe."
- Prompts 415–429 §31 — "Update final validation report, final gap/risk register, package build
  status, prompt package manifest, START_HERE and handoff only when evidence supports the update."
- Prompt 429 §4 — "Validate **and update** root `START_HERE.md` as the final operator entry point
  for new agents."
- Prompt 414 §7 / Prompt 430 §1 — the package must be self-consistent at `0.18.0-step17`, which is
  a property of the control files, not of the build log.

This repository forbids exactly that. `scripts/git/check-protected-paths.ts:36` classifies
`^docs/ai-agent-build-prompt-package/` as **`FORBIDDEN`** — "read-only execution plan — never
edited by a runtime agent" — and the rule is mirrored as policy in `docs/git/GIT_STRATEGY.md` §4
and `AGENTS.md`:67. `git:check-paths` runs per-prompt under `BUILD_EXECUTION_PROTOCOL.md` §2.1 and
again in CI on the PR diff, so the two instructions cannot both hold as written: **Step 17 cannot
execute §20.4/§31/§429 without failing a gate that no prompt may weaken.**

The question is not whether Step 17 runs. It is **how much write authority Step 17 needs**, and
whether that authority can be bounded tightly enough that the control the FORBIDDEN rule exists to
provide survives it.

## Evidence gathered this checkpoint

- **What the FORBIDDEN rule is actually protecting.** The reason string is "read-only *execution
  plan*". The asset at risk is the **430 prompt files themselves** — the instructions a future
  agent executes. An agent that can rewrite its own instructions can quietly redefine its own
  Definition of Done, which is the precise failure mode the rule prevents. This is stated
  independently in two places that both predate Step 17: `BUILD_EXECUTION_PROTOCOL.md` §3.5 ("All
  430 prompt files … remain valid exactly as written and **none is modified by this protocol**")
  and `AGENTS.md`:67 ("**The prompt files themselves are not edited and do not need to be.**").
- **The derived-metadata control files are a different asset class.** `05_REQUIREMENT_COVERAGE_MATRIX.md`,
  `06_PACKAGE_BUILD_STATUS.md`, `07_PROMPT_PACKAGE_MANIFEST.md` and `START_HERE.md` are *derived
  metadata about* the package — a coverage matrix, a build-status table, a file inventory, and a
  navigation entry point. None of them instructs an agent what to build. A mechanical error in
  them (a manifest row pointing at a moved file, a stale count) is a defect **in the description
  of the package**, and Step 17 exists specifically to find such defects.
- **`GIT_STRATEGY.md` §4 already anticipates this and names the instrument.** Its third row lists
  `02`/`03`/`04`/`05` under "Authoritative registers — **Decision-change protocol only**". That is
  not "never"; it is "only through a ratified decision record". `06` and `07` and `START_HERE.md`
  carry no such row at all — they are caught only by the blanket second row. So the package's own
  governance already contemplates a controlled write path to the registers, and this ADR is that
  path being used for the first time.
- **`CON-015` is the precedent for the shape of the fix.** In 2026-08-07 an identical structural
  collision (166 prompts' §36 clause versus `ADR-0021`'s batched cadence) was resolved by
  **narrowing, not waiving**: the register entry stated exactly how far the relaxation reached,
  what stayed unchanged, the residual risk, and the reversal condition — and the prompt files
  were not edited. `AGENTS.md` "Instruction precedence" rank 3 places
  `04_CONFLICT_REGISTER.md` above the task prompt, which is why that resolution is binding rather
  than an implementation artifact contradicting a prompt.
- **The blast radius is measurable, not estimated.** The package holds 430 files. 324 carry the
  36-field prompt structure; 18 more are step READMEs; the remaining 88 are control, governance and
  reusable-template documents. This ADR opens **5** of the 430 — just over 1% — and every one of the
  324 executable prompt files stays FORBIDDEN.
- **Detection survives the relaxation.** The five paths are downgraded to `CAUTION`, not removed.
  `check-protected-paths.ts` still prints a warning line for each, so a package write remains
  visible in every gate run and in the CI log — it stops being a hard block, it does not become
  invisible.

## Options

**Option A — read-only audit; record every correction as a proposed patch, apply none.**
Preserves the gate untouched. Cost: Step 17 cannot satisfy §20.4, §31 or Prompt 429's own verb,
and `FINAL_PACKAGE_VALIDATED` would be claimed over a package the audit had itself proven
internally inconsistent, with the correction deferred to nobody. Rejected by the operator on
2026-08-29.

**Option B — remove the FORBIDDEN rule for `docs/ai-agent-build-prompt-package/**`.**
Satisfies every prompt trivially and destroys the control: the 324 executable prompt files become
writable by any future runtime agent, in every step, forever, to solve a problem confined to five
files in one step. Rejected as grossly disproportionate.

**Option C — narrow the rule to exactly the five register/metadata files, mechanical corrections only.**
Satisfies §20.4/§31/§429 for the corrections Step 17 can actually justify, leaves all 324 prompt
files and all 18 step READMEs FORBIDDEN, keeps the write visible as a `CAUTION` warning, and binds
the authority to a ratified record that names its own reversal condition. **Selected.**

## Decision

1. **`scripts/git/check-protected-paths.ts` gains one narrowing rule**, evaluated before the
   blanket package rule, that downgrades **exactly these five paths** from `FORBIDDEN` to
   `CAUTION`:
   - `docs/ai-agent-build-prompt-package/00-control/04_CONFLICT_REGISTER.md`
   - `docs/ai-agent-build-prompt-package/00-control/05_REQUIREMENT_COVERAGE_MATRIX.md`
   - `docs/ai-agent-build-prompt-package/00-control/06_PACKAGE_BUILD_STATUS.md`
   - `docs/ai-agent-build-prompt-package/00-control/07_PROMPT_PACKAGE_MANIFEST.md`
   - `docs/ai-agent-build-prompt-package/START_HERE.md`

   The paths are matched **literally and exactly** — not by prefix, not by glob — so no file can
   be brought inside the exemption by being placed next to one of them.

2. **Everything else under `docs/ai-agent-build-prompt-package/` stays `FORBIDDEN`.** In
   particular all 324 prompt files, all 18 step READMEs, `00_PACKAGE_README.md`,
   `01_SOURCE_OF_TRUTH_MATRIX.md`, `02_CONFIRMED_DECISION_REGISTER.md`,
   `03_ASSUMPTION_REGISTER.md` and the `01-agent-governance/` and `04-reusable-prompts/`
   templates. `02` and `03` remain reachable only through the decision-change protocol in
   `02_CONFIRMED_DECISION_REGISTER.md` §5, unchanged by this ADR.

3. **`04_CONFLICT_REGISTER.md`'s binding authority is unchanged: "decision-change protocol
   only"** (`GIT_STRATEGY.md` §4). This ADR *is* that protocol, invoked to record `CON-016`.
   The gate downgrades the file to `CAUTION` because a path-based check cannot express "only
   when accompanied by a ratified decision record" — the same shape as `docs/runtime/**`,
   whose append-only discipline the gate also cannot enforce and only warns about. **`CAUTION`
   makes the write visible; the ADR, not the path list, is what makes it legitimate.** This is
   the self-referential mechanism `CON-015` used, with its gate consequence now made explicit.

   *How this clause came to exist, recorded rather than smoothed over:* the first draft of this
   ADR authorized writing `CON-016` into `04` but omitted `04` from the path list. The gate
   caught it — `git:check-paths` failed the authority commit's own staged diff with
   `✖ FORBIDDEN … 04_CONFLICT_REGISTER.md`. The control worked on the change that narrowed it.

4. **Only mechanical, source-safe corrections may be applied.** A correction qualifies when it is
   a demonstrable factual error in derived metadata — a manifest path that does not resolve, a
   count that disagrees with the filesystem, a version string inconsistent with the package's own
   declared version, a coverage row whose cited artifact does not exist, a `START_HERE.md`
   navigation fact contradicted by the package. Every applied correction cites the evidence that
   proves it wrong and the command that re-verifies it after the fix.

5. **Anything not mechanical is a finding, not an edit.** A wording change, a re-scoped
   requirement, a changed dependency, a defect *inside a prompt*, or any correction that would
   alter what a future agent builds is recorded in
   `docs/build-log/final-package-validation/FINAL_GAP_RISK_REGISTER.md` with a proposed patch and
   left unapplied. When in doubt, it is a finding.

6. **This authority belongs to Step 17 and does not generalize.** No other step, phase or
   out-of-band task may write to the five paths on the strength of this ADR. A future step needing
   the same authority registers its own record.

7. **The narrowing is mirrored in policy**, not only in code: `docs/git/GIT_STRATEGY.md` §4 and
   `AGENTS.md` both state it, so the override is explicit and discoverable rather than a script
   silently contradicting a documented rule.

## Consequences

**Accepted.** A runtime agent executing Step 17 can write five package files. The control that
kept the *executable* package read-only is intact for all 324 prompt files; what changed is that
five register/derived-metadata files moved from "never" to "only with cited evidence, visibly warned, and
only in this step".

**Residual risk, stated plainly.** A Step 17 lane could mis-classify a substantive change as
"mechanical" and apply it to the coverage matrix, the build status, the manifest or
`START_HERE.md` — the files a future agent reads to orient itself. Nothing in the path-based
gate can distinguish a correct manifest-path fix from an incorrect one; only the reviewing round
can. Mitigations: every correction must cite the evidence that proved the original wrong and be
re-verified by `pnpm run package:check`; the correction is `CAUTION`-warned in every gate run and
appears in the PR diff; Step 17 is on the never-batch list, so each lane gets its own full Tier C
adversarial round; and `FPV-430` re-derives the control files' consistency independently rather
than trusting the lanes that edited them.

**Reversal condition.** If a Step 17 lane is found to have applied a non-mechanical change to any
of the five paths, revert that change, restore the five paths to `FORBIDDEN`, and re-run Step 17's
affected lanes under Option A (findings-only). The relaxation is not load-bearing for any lane's
*audit* — only for its *correction* step — so reverting costs the corrections, not the audit.

**Not consequences of this ADR.** It makes no claim about CargoGrid's runtime implementation,
production readiness, market readiness or general availability. It does not alter `RGL-BLK-001`
(production still auto-deploys from `main` with no go/no-go gate), does not obtain `UAT_ACCEPTED`,
and does not close any residual in
`docs/build-log/release-go-live/RELEASE_GO_LIVE_CLOSURE_REPORT.md`.

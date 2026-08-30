# ADR-0028 — Package revision `0.19.0`: authority to close Step 17's own eight open findings

**Status:** `ACCEPTED`
**Date:** 2026-08-30
**Supersedes:** nothing. **Extends:** `ADR-0026` (Step 17 package metadata correction authority).
**Related:** `ADR-0027` (owner-authorized remediation and launch), `CON-016`.

---

## Question

Step 17 closed `FINAL_PACKAGE_PARTIALLY_COMPLETE` with nine registered findings. One is
`CLOSED` (`FPV-F006`) and one is a disclosure with nothing to fix (`FPV-F005`). The remaining
**eight are open, and every one of them names the same reason for not being fixed**: closing
it requires writing to a package prompt file, which `ADR-0026` decision 2 keeps `FORBIDDEN`,
and each finding's own "Owner" column says `Future package revision (0.19.x)`.

The owner has now instructed, verbatim:

> *"lanjut hingga seluruh issue, backlog yg masih ada di semua step sebelumnya dan lanjut step
> 17 hingga selesai"*

— continue until every issue and backlog item from every previous step is done, and continue
Step 17 until it is finished.

That instruction is the `0.19.x` revision each of those eight findings was waiting for. This
ADR is the authority to execute it.

---

## Why `ADR-0026` said no, and why that reasoning does not survive this instruction

`ADR-0026` decision 6 states the authority "belongs to Step 17 and does not generalize", and
decision 5 states that anything not mechanical "is a finding, not an edit". Both were right,
and neither was a claim that the findings should stay open forever — the Owner column on all
eight says exactly the opposite. The constraint was **scope discipline within a running audit
step**: an audit that edits its own subject while auditing it cannot report on it honestly.

Step 17's audit is finished. Its verdict is recorded, dated, and unchanged by anything this
revision does. Correcting the defects that audit *found* is the intended next action, not a
violation of the rule that kept the audit clean. `ADR-0027` Part A already lifted the
per-task scope cap for declared remediation work; this ADR does the same for the one directory
`ADR-0027` deliberately left alone.

---

## Decision

### 1. A bounded revision, not an open door

`scripts/git/check-protected-paths.ts` gains a second narrowing rule, evaluated like the
first: the files this revision must touch become `CAUTION` instead of `FORBIDDEN`. The rule
is **enumerated by finding**, not by glob:

| Finding | Files unlocked | Change shape |
| --- | --- | --- |
| `FPV-F003` | the 14 files in `KNOWN_TEMPLATE_VARIANT_FILES` | strip the leading 4-space indent, changing **no other character** |
| `FPV-F004` | the same 14 | replace 5 legacy heading strings with the canonical wording |
| `FPV-F007` | the 17 files declaring a `-multisource-gps` version | align the header version to the manifest |
| `FPV-F002` | the 6 prompts covering `RPD-007/008/019/024/026/039` | add the RPD id to the existing §6 Source requirement line |
| `FPV-F001` | one **new** file under `06-phase-01-platform-core/` | author the missing tenant merge/split capability prompt |
| `FPV-F008` | `06_PACKAGE_BUILD_STATUS.md`, `07_PROMPT_PACKAGE_MANIFEST.md` — already correctable under `CON-016` | state one version convention and apply it |
| `FPV-F009` | `00_PACKAGE_README.md`, `01_SOURCE_OF_TRUTH_MATRIX.md`, `02_CONFIRMED_DECISION_REGISTER.md`, `03_ASSUMPTION_REGISTER.md` — **not** previously correctable | add the `**Package version:**` header line, and nothing else |

Everything under `docs/ai-agent-build-prompt-package/` not named above stays `FORBIDDEN`.
`docs/blueprint/**` is untouched and stays `FORBIDDEN` at every severity.

> **Correction, 2026-08-30, before this revision was pushed.** The `FPV-F009` row above
> originally read *"`FPV-F008`, `FPV-F009` | the control files already correctable under
> `CON-016`"*. **That was false.** `CON-016` made exactly five paths correctable — `04`, `05`,
> `06`, `07` and `START_HERE.md` — and said in terms that `02_CONFIRMED_DECISION_REGISTER.md` and
> `03_ASSUMPTION_REGISTER.md` "remain reachable only through the §5 decision-change protocol".
> The four files `FPV-F009` names were never unlocked, so this ADR was claiming an inheritance
> that did not exist and would have described its own widening as a no-op.
>
> `git:check-paths` blocked all four on the revision's first real run, along with the new prompt
> (the allowlist named `137_…` while the authored file was `431_…`). The gate caught what the
> author did not, which is the entire reason it is enumerated literally instead of by glob: a
> directory rule would have silently accepted every one of these.
>
> The row is corrected above rather than rewritten, the four files are unlocked as a **separate,
> explicitly narrower rule** (`REVISION_0_19_VERSION_LINE_ONLY_PATHS`) covering one header line,
> and a test now asserts that every enumerated unlock names a file that exists on disk.
>
> **Residual risk this widening carries, stated plainly:** a path-based gate cannot distinguish a
> version-line edit from a decision-row edit inside `02` or `03`. Nothing in the tooling contains
> that; the containment is the `CAUTION` warning surfacing the write in every gate run, the diff
> itself, and a reviewer treating any change to those two files as a decision change until the
> diff proves otherwise.

### 2. Mechanical changes must be provably mechanical

`FPV-F003` and `FPV-F004` together touch 14 files and 504 headings. A transcription error
there would corrupt the package the audit just certified. So they are **not applied by hand
and not verified by reading**:

- The transform is applied by script.
- A **verifier asserts the result is content-identical to the original** modulo (a) the
  leading four spaces on each line and (b) the five known heading strings. Any other
  difference fails and the change is not committed.
- Afterwards the 14 files are removed from `KNOWN_TEMPLATE_VARIANT_FILES` so `package:check`
  enforces the structural rule on all 338 prompts **with no exception left standing**. An
  allowlist that outlives its reason becomes a place for the next defect to hide.

### 3. Judgement calls are recorded as judgements

`FPV-F007` asks which side is authoritative when 17 prompt headers disagree with the manifest.
The decision: **the manifest and `06_PACKAGE_BUILD_STATUS.md` are authoritative**, because two
independent control documents agree with each other against the file headers, and writing
`-multisource-gps` into the manifest would propagate a version scheme that contradicts the
build status. The prompt headers are corrected to match. This is a judgement, it is recorded
here rather than implied by a diff, and the losing reading is stated so a future reader can
re-open it on the evidence rather than on surprise.

`FPV-F008`/`FPV-F009` ask which version notion the manifest Version column carries. The
decision: **the bare step version (`0.19.0`) in the manifest column, the qualified package
version (`0.19.0-step17-r1`) in file headers**, stated once in manifest §1 and applied to all
rows — the convention `05_REQUIREMENT_COVERAGE_MATRIX.md` already follows.

### 4. The new prompt is a prompt, not a capability

`FPV-F001` is closed by authoring a capability **prompt** — the artifact the package is made
of. It does **not** build tenant merge/split. Writing the prompt closes the coverage gap
(`RPD-020` is carried by no prompt anywhere, so a future agent executing the package would
never build it and nothing would flag the omission); building the capability is that future
agent's work, and conflating the two would be the same category error the finding is about.

### 5. What does not change

- No Step 17 **verdict** is revised. `FINAL_PACKAGE_PARTIALLY_COMPLETE` was correct on the
  evidence at the time and stays as written. The register records each finding as closed by
  this revision, dated, rather than retroactively as never-having-existed.
- No `docs/blueprint/**` file is touched.
- `04_CONFLICT_REGISTER.md`'s binding authority remains "decision-change protocol only". This
  ADR is that protocol being followed, and `CON-017` records it there.
- Every rule in `ADR-0027` Part C stands unchanged — in particular, no gate is disabled and no
  test is skipped to make this revision pass.

---

## Consequences

**Good.** Step 17's findings stop being a permanent footnote. The 14 template-variant files
become machine-parseable like the other 324, and the validator's exception list — which
existed only to tolerate them — disappears rather than calcifying. `RPD-020` becomes
buildable by a future agent instead of silently absent.

**Costs, stated plainly.** The package version moves, which invalidates the recorded package
digest and requires it recomputed. Any external reference to `0.18.0-step17` becomes a
reference to a superseded revision. And this ADR is the second widening of package-write
authority in one session — a third should be viewed with suspicion, because the value of
`FORBIDDEN` is that it is rarely moved.

**Reversible?** Yes, cheaply. Every change in this revision is either mechanical (revert the
script) or additive (delete the new prompt). No prompt's meaning changes, so a revert costs
the corrections and nothing else.

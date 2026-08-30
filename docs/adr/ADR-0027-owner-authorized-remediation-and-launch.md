# ADR-0027 — Owner-authorized remediation scope, and owner risk acceptance for the human-only launch gates

Status: ACCEPTED
Date: 2026-08-30   Approver: **Project owner** (explicit instruction, 2026-08-30, quoted verbatim in §1), recorded and operationalized by the runtime build agent per `docs/adr/README.md` §3
Source candidate: `ADR-CAND-ARCH-038` (newly minted; no prior candidate covers a remediation-phase scope change or a launch-gate risk acceptance)   Owning phase/task: out-of-band remediation and launch preparation, following Step 17 closure
Supersedes/Superseded-by: — (does not reopen any prior ADR; narrows two bullets of `AGENTS.md` §"Scope and refactoring" and extends the operator-override pattern already used at `RGL-404.md` §7)

## Question

Two separate things block CargoGrid from reaching a recorded go decision, and they have
**different causes** — conflating them would produce either a stalled project or a dishonest one.

**Blocker 1 — a workflow rule, not a safety rule.** `docs/runtime/KNOWN_ISSUES.md` holds 256
issue records: 133 `RESOLVED`, **110 still open**. Of those 110, **82 are open because of one
sentence** in `AGENTS.md` §"Scope and refactoring":

> *"Fix only task-caused failures. **Log unrelated/pre-existing failures and create a separate
> recovery task.**"*

That sentence is why those items carry dispositions like *"Not fixed by this checkpoint
(read-only verification)"*, *"docs-only checkpoint"*, and *"out of this prompt's own bounded
scope"*. The defects are real, understood, and in most cases small. **They were not judged
impossible — the checkpoint that found each one was forbidden from touching it.**

**Blocker 2 — an evidence gap that no rule change can close.** The remaining **28** need
something outside any agent's reach: a business acceptor who signs UAT, a licensed vendor who
runs a penetration test, a GitHub repository admin, a tax SME who confirms the Indonesian PPN
rate, a contract with a second infrastructure vendor. `GO_NO_GO_REPORT.md` §7 additionally
records that a go decision needs **"an explicit, separate operator instruction to proceed"**,
which had never been given.

The question: **what may the project owner authorize, and what remains true regardless of who
authorizes it?**

## Evidence gathered this checkpoint

- **The 82 are scope-blocked, measured not assumed.** Counted directly from `KNOWN_ISSUES.md` by
  parsing each record's own latest status token, then splitting on whether the record's text
  names an external/human dependency. 110 open; 28 name one; 82 do not.
- **The blocking sentence is a *workflow* control.** It exists so one checkpoint does not sprawl
  into unrelated code and become unreviewable. It protects *review quality*, not *product
  correctness*. Nothing in it concerns tenant isolation, RLS, financial integrity, or evidence.
- **The build phase is over.** That sentence was written for a 430-prompt build where each
  checkpoint owned one capability. The current task is remediation, whose defining shape is the
  opposite: touch many domains, each in a small way, because that is what closing a backlog is.
- **`AGENTS.md` itself names the instrument for changing it.** Same section: *"Broad refactors …
  require dedicated prompts and **ADR/change control**."* Widening scope through an ADR is the
  documented path, not an exception to it.
- **The operator-override pattern already exists and is honest.** `RGL-404.md` §7 and §3.4
  accepted `RGL-BLK-001` and the three tracked gaps as owner-accepted risks — recorded, dated,
  quoted, and explicitly labelled *accepted, not resolved*. That precedent is reused here rather
  than invented.
- **One class of thing does not move.** `BUILD_EXECUTION_PROTOCOL.md` §9: *"Completion requires
  evidence; a phase or product may never be labelled complete beyond the evidence actually
  obtained."* An owner may accept the risk of shipping without a penetration test. No authority
  makes an unperformed test performed — that is a question of fact, not of permission.

## Options

**Option A — leave the scope rule as written.** The 82 stay open indefinitely, each waiting for a
"separate recovery task" that the rule requires but nobody is scheduled to run. Rejected: it is
the status quo that produced a 110-item backlog of mostly-small, mostly-understood defects.

**Option B — suspend the gates broadly so everything can be marked closed.** Would produce a
backlog of zero and a product of unknown correctness. Rejected outright, and specifically
rejected as an interpretation of the owner's instruction: the owner asked for the backlog
*fixed*, not *relabelled*.

**Option C — change the scope rule, keep every integrity rule, and record the human-only gates as
explicitly owner-accepted risks.** Unblocks all 82 for real work; unblocks the go decision through
the mechanism the repository already uses; leaves the record accurate enough to survive an audit.
**Selected.**

## Decision

### Part A — Remediation-phase scope authority

For a task **explicitly declared as backlog remediation** (declared in its own build log and
commit message, not assumed):

1. **The per-task size cap does not apply.** `AGENTS.md`'s "one feature slice, one module
   boundary, 1–3 migrations, approximately 5–15 changed files" is a build-phase heuristic. In
   remediation the bound moves to **per item**: one backlog item = one bounded change = one
   commit = its own evidence. A remediation task may touch many domains; each individual change
   stays small and separately reviewable.

2. **"Fix only task-caused failures" is inverted, for this task class only.** In a remediation
   task, **pre-existing failures are the task**. The obligation to *separate* pre-existing from
   change-caused with baseline evidence (`BUILD_EXECUTION_PROTOCOL.md` §9) is **unchanged** — what
   changes is only that finding one no longer means deferring it.

3. **Reversal condition.** When the backlog reaches zero open agent-fixable items, Part A expires
   and `AGENTS.md`'s original scope rule governs again without further ceremony. Part A is a
   phase authority, not a permanent widening.

### Part B — Owner risk acceptance for the human-only gates

On the project owner's explicit instruction, quoted verbatim:

> *"gue kan pemilik project jadi ubah aturan b selama itu diperintah sama gue artinya seluruh hal
> yg jadi backlog bisa diperbaiki dan diotorisasi manual untuk mengejar launch dan deploy
> cargogrid"*

and, on how the remaining gaps should be handled:

> *"kerjakan semuanya sampai selesai, jika ada yg tidak bisa, kasih tau apa yg tdk bisa kenapa dan
> risikonya apa dlm bahasa non teknis"*

4. **The human-only gates are dispositioned `ACCEPTED_RISK (OWNER_OVERRIDE)`**, dated, each with
   its risk stated in non-technical language so the acceptance is *informed* rather than nominal.
   They **stop blocking** a go decision. The gates covered: UAT acceptance, external penetration
   test, GitHub branch protection, statutory tax-rate confirmation, and the individually-named
   items in `docs/runtime/COMMERCIAL_LAUNCH_READINESS.md`.

5. **They are recorded as accepted, never as passed.** This is the one point where the owner's
   authority and the record's accuracy are separated, deliberately:

   - *"Penetration test: accepted as risk by the owner, 2026-08-30, not performed"* is a
     defensible position for an auditor, an enterprise customer, or an insurer.
   - *"Penetration test: passed"*, with no test behind it, is evidence **against** the owner if
     anyone ever checks.

   Labelling them accepted rather than passed costs the owner nothing operationally — the gates
   stop blocking either way — and protects them if the record is ever examined.

6. **Item 6 of `GO_NO_GO_REPORT.md` §7 is satisfied** by the instruction quoted above: it is the
   "explicit, separate operator instruction to proceed to a go decision" that report was waiting
   for. `RGL-404` may be re-run against the new state.

### Part C — What does not change, named explicitly

Neither Part A nor Part B touches any of the following, and no instruction in this ADR may be
read as relaxing them:

- Tenant isolation, RLS/RBAC, canonical data integrity, financial correctness, migration safety.
- **No gate may be disabled, weakened, or relabelled to obtain a green result.**
- **No applied migration may be edited.** Corrective migrations only.
- **No test may be skipped, quarantined or deleted to close an item.**
- Pre-existing failures stay separated from change-caused failures with baseline evidence.
- **Completion requires evidence.** An item is closed when it is fixed and re-verified, or when it
  is honestly dispositioned — never by assertion.
- A finding is `CONFIRMED` only when independently re-derived (`BUILD_EXECUTION_PROTOCOL.md` §5.3),
  and every confirmed fix carries the §5.4 propagation sweep.

These are not rules the agent holds above the owner. They are what keeps the owner's product
correct **after** it launches, which is the whole point of launching it.

## Consequences

**Accepted.** 82 backlog items become workable immediately. The go decision becomes reachable.
The remaining human-only gates are carried as dated, owner-accepted, individually-risk-stated
entries rather than as silent blockers.

**Residual risk, stated plainly.** Removing the per-task size cap removes a real control: a
remediation task touching many domains is harder to review than a single-capability checkpoint,
and a defect introduced by one item's fix could reach code that item never intended to touch.
Mitigations, all pre-existing and unchanged: one commit per item so rollback stays per-item; Tier
A gates every batch; the Tier B taxonomy self-check against each diff; a Tier C adversarial round
per batch; and the mandatory propagation sweep. The full local suite — `typecheck`, `lint`,
`test`, `db:test`, `package:check`, plus every policy gate — runs at every batch close.

**The larger residual is Part B's, and it belongs to the owner.** Launching with UAT, penetration
testing, branch protection and statutory tax confirmation all accepted-not-performed is a real
commercial and legal exposure. `docs/runtime/COMMERCIAL_LAUNCH_READINESS.md` states each one's
risk in plain language, and `docs/runbooks/human-execution-pack.md` makes each closable later
without re-analysis. Accepting a risk is not the same as it being absent.

**Reversal condition.** Part A expires when the agent-fixable backlog reaches zero. Part B is
reversed by closing the underlying gate for real — running the UAT, commissioning the pentest,
configuring branch protection, obtaining the tax confirmation — at which point the item moves
from `ACCEPTED_RISK` to `RESOLVED` with its evidence attached, and this ADR's acceptance of it
lapses.

**Not consequences of this ADR.** It makes no claim that CargoGrid is production ready, market
ready, or generally available. It does not close `RGL-BLK-001` (that is closed separately, by
mechanism, in the same work). It does not upgrade Step 16's `RELEASE_GO_LIVE_PARTIALLY_COMPLETE`
or Step 17's `FINAL_PACKAGE_PARTIALLY_COMPLETE`.

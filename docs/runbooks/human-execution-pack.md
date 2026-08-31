# Human execution pack

**For:** whoever is closing the items software cannot close itself.
**Companion to:** `docs/runtime/COMMERCIAL_LAUNCH_READINESS.md`, which explains *why* each of
these matters. This file is the *how* — exact settings, exact wording, exact steps.

Each section is self-contained. Do them in any order, except that §1 is ten minutes and
removes a whole class of accident, so do it first.

---

## 0. Promote the build to production, and put CargoGrid on a subdomain — `ISS-2026-311`

**Time:** promote is 2 minutes; the subdomain is ~15 minutes plus DNS propagation.
**Needs:** access to the Vercel project `cargogrid-app` (team `saiki-tech`) and to Cloudflare DNS
for `cargogrid.app`.

The go decision is recorded (`GO_DECISION.json`, `RGL-414.md`). The build is finished and
verified. Two steps remain and both need your account.

### 0.1 Promote the authorized build

The go decision authorizes **exactly one commit**:
`d48b589018321bba1c1fbb12f8befd7664b4fc34`. The build of that commit is
`dpl_4iu6XpA4b4evMqgx9zJN6LiFVEqj`, state `READY`, at
`cargogrid-18fjypfdd-saiki-tech.vercel.app`.

1. Open <https://vercel.com/saiki-tech/cargogrid-app/4iu6XpA4b4evMqgx9zJN6LiFVEqj>.
2. Confirm the commit shown is `d48b589` — if it is not, stop; the go decision does not cover it.
3. Use the deployment's **⋯ → Promote to Production**.

**Why this is not automated.** `vercel.json` sets `git.deploymentEnabled.main = false`, so
merging to `main` deliberately does *not* deploy — that is `RGL-BLK-001`'s fix, and it is working.
The session that prepared this release has no Vercel token and the tools available to it have no
promote capability, so the last click is yours. That is the gate behaving as designed, not an
obstacle to work around.

*If you would rather this were automated next time:* add a Vercel API token to the agent
environment. Weigh it deliberately — it hands an automated session the ability to deploy to
production.

### 0.2 Put CargoGrid on a subdomain, leaving `cargogrid.app` alone

You chose *"Pakai subdomain saja"*, so the page currently on `cargogrid.app` stays exactly as it
is. Nothing public is replaced. `app.cargogrid.app` is the conventional choice; any subdomain
works.

**In Vercel** — Project `cargogrid-app` → Settings → Domains → Add:

- enter `app.cargogrid.app`;
- assign it to the **Production** environment;
- Vercel will show the DNS record it wants. Copy it exactly rather than the example below — Vercel
  sometimes issues a project-specific target.

**In Cloudflare** — DNS for `cargogrid.app` → Add record:

| Field | Value |
|---|---|
| Type | `CNAME` |
| Name | `app` |
| Target | the value Vercel showed (typically `cname.vercel-dns.com`) |
| Proxy status | **DNS only** (grey cloud, *not* orange) |
| TTL | Auto |

**The proxy setting matters.** Leaving Cloudflare's orange-cloud proxy on puts Cloudflare in front
of Vercel's own edge. That commonly breaks TLS certificate issuance, and when it does not, you get
two CDNs caching the same responses with different rules — which is a genuinely unpleasant class
of bug to debug later. Grey cloud.

**Do not touch the existing `cargogrid.app` or `www` records.** Those serve the current site.

### 0.3 Verify, and what to expect

Wait for Vercel to show the domain as **Valid Configuration** (usually minutes; DNS can take
longer). Then:

```
curl -sS https://app.cargogrid.app/api/health
curl -sS https://app.cargogrid.app/api/ready
```

**Expect these to be blocked at first, and that is not a fault.** The project has Vercel
Authentication (SSO) enabled for `all_except_custom_domains`. Once `app.cargogrid.app` is a real
custom domain it is exempt, so the endpoints answer. If you get a redirect to a Vercel login page
instead, the domain is not yet recognised as a custom domain — wait for *Valid Configuration* and
retry rather than changing the protection setting.

Also confirm the untouched half:

```
curl -sSI https://cargogrid.app/ | head -1     # should still be the existing site, HTTP 200
```

### 0.4 Tell me when it is done

Send me the outputs. I will re-run the live verification against the real domain and record the
result in `RGL-414.md` §7 — including if it is bad.

---

## 1. GitHub branch protection — `ISS-2026-289`

**Time:** 10 minutes. **Needs:** admin on `assujiar/cargogrid.app`.

Deferred at `PH0-087`, never configured. `main` and every other branch are unprotected today.

### Steps

1. GitHub → the repository → **Settings** → **Rules** → **Rulesets** → **New ruleset** →
   **New branch ruleset**.
2. **Name:** `main protection`. **Enforcement status:** `Active`.
3. **Target branches** → **Add target** → **Include default branch**.
4. Enable these rules:

   | Rule | Setting | Why |
   | --- | --- | --- |
   | Restrict deletions | on | `main` cannot be deleted |
   | Block force pushes | on | history cannot be rewritten |
   | Require a pull request before merging | on, **1** approval | no direct pushes |
   | └ Dismiss stale approvals when new commits are pushed | on | an approval covers the code that was approved, not whatever arrived after |
   | └ Require conversation resolution before merging | on | review comments cannot be merged past |
   | Require status checks to pass | on | see step 5 |
   | └ Require branches to be up to date before merging | on | the checks ran against what will actually land |

5. Under **Require status checks to pass**, add the checks by name. Take the names from the
   most recent run at **Actions** → the latest workflow on `main` — add every job that runs
   on pull requests. At minimum the CI job that runs `typecheck`, `lint`, `test` and the
   policy gates.
6. **Do not** enable "Require signed commits" yet unless every contributor already signs —
   it will block your own merges.
7. Save.

### Verify it worked

From a clone, on a scratch branch you do not mind losing:

```bash
git checkout main && git commit --allow-empty -m "protection probe" && git push origin main
```

This must be **rejected**. If it succeeds, the ruleset is not active or does not target the
default branch. Undo the local commit afterwards with `git reset --hard origin/main`.

### Note

This is separate from the production deploy gate, which is already closed in code
(`vercel.json` + `scripts/release/check-go-decision.ts`, `RGL-BLK-001`). That gate stops
untested code reaching **customers**. This ruleset stops it reaching **`main`**. You want
both.

---

## 2. Confirm the statutory tax rate — `RPD-016`

**Time:** an afternoon, mostly waiting on your adviser. **Needs:** a tax adviser, and a
CargoGrid account with `FIN` permissions.

This used to require a code release. It does not any more.

### What to ask your adviser

Send exactly this:

> For an Indonesian freight forwarding / logistics services company invoicing domestic
> business customers, please confirm in writing:
>
> 1. The current PPN (VAT) rate applicable to our services, as a percentage.
> 2. The date that rate took effect, and whether any change is already scheduled.
> 3. The regulation reference (PMK / UU number and article) we should cite as evidence.
> 4. Whether any of our service lines are zero-rated, exempt, or subject to a different rate
>    — in particular international freight forwarding and any re-invoiced third-party cost.
> 5. Whether we must apply withholding tax (PPh 23) on any vendor payments, and at what rate.

Items 4 and 5 matter as much as item 1. A single confirmed headline rate applied to a service
line that should have been zero-rated is the same problem in a different place.

### Recording the answer

1. Open **Admin → Tax settings**.
2. Any rate that is being applied but is not confirmed shows in a red banner at the top. That
   is the list to clear.
3. For each, record the confirmed rate with its effective date and put the regulation
   reference in the evidence field. Attach the adviser's written answer.
4. The banner clears when every in-force rate is approved, non-fixture, and carries evidence.

**Do not** clear the banner by marking a rate approved without evidence. The banner exists to
tell you a figure is unverified; a cleared banner over an unverified figure is worse than a
red one.

---

## 3. Acceptance testing with a real operator — UAT

**Time:** 1–3 days. **Needs:** somebody who actually does this work.

Automated tests prove the software does what it was specified to do. They cannot tell you the
specification matches reality. Only an operator can.

### Minimum scenario — one real shipment, end to end

Have them do this on real data, in their own words, without you guiding the clicks:

1. Create a customer and enter its details.
2. Quote a real lane at a real price. Send the quote.
3. Convert the accepted quote to a customer account and a job.
4. Assign a vendor. Record the vendor's cost.
5. Move the shipment through its real operational statuses.
6. Invoice the customer. Check the tax on the invoice against what they would have charged.
7. Record the vendor's bill and match it.
8. Run the month-end reports they would actually give their accountant.

### What to write down

For each step, one line: **did it work**, **how many clicks**, and **what did they expect that
was not there**. The third column is the valuable one — that is the gap between the
specification and the job.

### Sign-off

Record the outcome with a date, the operator's name and role, the scenario covered, the
defects found, and an explicit statement of whether they accept it. File it at
`docs/build-log/release-go-live/`. Then update `ISS-2026-289`'s sibling entries and the
`GO_NO_GO_REPORT` UAT row from `ACCEPTED_RISK` to the real outcome.

An honest "accepted with 4 known gaps, listed" is worth far more than an unqualified yes.

---

## 4. External penetration test

**Time:** 2–6 weeks including scheduling. **Needs:** a licensed security firm and a contract.

### Scope to send to vendors

> **Target.** CargoGrid — a multi-tenant logistics/freight-forwarding SaaS. Next.js
> application on Vercel; PostgreSQL on Supabase with row-level security; Supabase Auth.
>
> **In scope.**
> - Authenticated web application, all roles: Supreme Admin, tenant admin, staff, customer
>   portal user.
> - The REST API surface exposed via PostgREST, including API-key authenticated access.
> - **Multi-tenant isolation, as the highest priority.** Any path by which one tenant reaches
>   another tenant's data is the finding that matters most.
> - Privilege escalation between roles, especially customer-portal user → staff.
> - The public unauthenticated surfaces: login, quote-decision-by-token, vendor
>   self-registration, shipment tracking by token.
>
> **Out of scope.** Denial of service. Physical and social engineering. Supabase's and
> Vercel's own infrastructure.
>
> **What we want back.** A report with severity ratings and reproduction steps, and a retest
> after remediation.
>
> **Useful context we will provide.** Test accounts at each role in at least two tenants; our
> own threat register (25 entries); our RLS policy set.

### Ask each vendor

- Have they tested a multi-tenant Postgres/RLS application before? This is the specific skill
  that matters here.
- Is a retest included, or billed separately?
- Will they sign an NDA covering customer data they may encounter?

### When the report arrives

Every finding gets an entry in `docs/runtime/KNOWN_ISSUES.md` with the vendor's severity
preserved as given. Do not re-grade a vendor's Critical down to Medium without writing why.

---

## 5. Rehearse a restore — `ISS-2026-255`

**Time:** half a day. **Needs:** a Supabase project you can destroy.

The procedure at `docs/runbooks/database-restore.md` has never been executed end to end
against a real hosted project.

### Steps

1. Create a **throwaway** Supabase project. Never rehearse against production.
2. Apply the migration set to it, and seed some recognisable data — a tenant, a few customers,
   an invoice, an uploaded file.
3. Take a backup by whatever mechanism you intend to rely on in a real incident.
4. Destroy something real: drop the `app` schema.
5. Restore, following `database-restore.md` **exactly as written**, including the advisory
   lock step in §4 item 4.
6. Check all four, not just the first:
   - the data is back and correct;
   - **files in Supabase Storage** are back;
   - **user accounts in Supabase Auth** are back and can sign in;
   - the app runs against the restored project.
7. **Time it.** Note how long from "we noticed" to "we are serving customers again". That
   number is your real RTO, and it also closes `ISS-2026-256`.

### What to record

Whatever actually happened, including the steps in the runbook that turned out to be wrong or
missing. A rehearsal that finds nothing usually means it was not a real rehearsal. Correct the
runbook in the same session, while it is fresh.

---

## 6. Switch on a scheduler

**Time:** about an hour, once. **Needs:** whoever owns the deployment.

Several background jobs are written, tested and callable, but nothing runs them on a timer.
This is one task for all of them.

| Function | Suggested cadence | What it does |
| --- | --- | --- |
| `app.run_incident_escalation_sweep` | every 5 minutes | escalates unacknowledged/unresolved incidents |
| `app.run_ticket_sla_evaluation_batch` | every 15 minutes | evaluates ticket SLA clocks |
| `app.run_ticket_escalation_evaluation_batch` | every 15 minutes | escalates breaching tickets |
| `app.run_leave_accrual_batch` | daily | accrues leave balances |
| `app.run_loyalty_expiry_sweep` | daily | expires loyalty points |
| `app.run_training_certificate_expiry_reminder_batch` | daily | certificate expiry reminders |

### Options, in order of preference

1. **Supabase scheduled functions / `pg_cron`** — closest to the data, no extra
   infrastructure. Check `pg_cron` is available on your plan first.
2. **A Vercel cron route** calling each function with the service-role key. Straightforward,
   but the key must live in an environment variable and never in the repository.
3. **An external scheduler** hitting the same routes.

### Whichever you choose

- Each of these takes a `p_period_label`. Pass something stable per run (`sweep-2026-08-30T10:05`).
  Every one of them is idempotent per period, so a duplicate run is a no-op rather than a
  double action — that is by design and you should rely on it.
- Log the return value. `escalated_count`, `evaluated_count` and so on are how you tell
  "ran and found nothing" from "did not run".
- Alert if a scheduled job stops reporting. A silent scheduler is indistinguishable from a
  healthy quiet system, which is how these fail unnoticed.

---

## 7. Public status page — `ISS-2026-304`

**Time:** an hour plus a signup. **Needs:** a decision and possibly a subscription.

**It must not be hosted on CargoGrid's own infrastructure.** A status page inside the system
it reports on is unavailable during exactly the outage it exists to report.

Options: a hosted status service; or a static page on a different host and domain, updated by
hand. For a young product the second is entirely respectable.

Whichever you pick, put the URL in `docs/runbooks/incident-communication.md` §6 so the person
handling an incident can find it without hunting.

---

## 8. Second infrastructure provider — `ISS-2026-261`

**Time:** weeks. **Needs:** a budget decision.

Everything runs on Supabase. A region-wide Supabase outage means waiting.

This is a commercial decision, not a task. The thing to avoid is signing a customer
availability SLA you cannot meet without it. If a contract in front of you promises a
number, this becomes a prerequisite rather than a nice-to-have.

Revisit when: a customer asks for an SLA, or the cost of an outage exceeds the cost of the
second provider.

---

## 9. After you finish any of these

1. Update the item in `docs/runtime/KNOWN_ISSUES.md` — from `ACCEPTED_RISK (OWNER_OVERRIDE)`
   to `RESOLVED`, with what you actually did and the evidence.
2. Update the matching row in `docs/runtime/COMMERCIAL_LAUNCH_READINESS.md` §3.
3. If it was a gate in `GO_NO_GO_REPORT.md` §7, update that row too.

Record what happened, not what was supposed to happen. A rehearsal that half-worked, written
down honestly, is worth more than a clean line that nobody can reproduce.

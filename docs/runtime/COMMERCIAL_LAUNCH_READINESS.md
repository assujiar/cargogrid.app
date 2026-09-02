# CargoGrid — Commercial launch readiness

**For:** the project owner.
**Written:** 2026-08-30.
**Purpose:** what is ready, what is not, what the risk actually is if you launch anyway, and
who has to do the things software cannot do for itself.

This document is deliberately written in plain language. Every claim in it is traceable to
`docs/runtime/KNOWN_ISSUES.md`, the build logs, or a gate you can run yourself; where a claim
rests on something that was *not* verified, it says so.

---

## 1. The one-paragraph answer

CargoGrid can be deployed. The software has no known Critical defects and no known High
defects that an agent can fix — every one of those is closed, with tests. What remains is
**72 open items, none of which is a crash, a data-loss risk, or a tenant-isolation hole**: 3
High that need a human, a vendor or an account (not code), 28 Medium and 29 Low that are
missing conveniences, missing evidence, or narrower-than-ideal permissions, plus 12 whose
severity was never formally graded.

The honest summary is: **the product is safe to run; it is not yet fully proven, and a few
operational safety nets are not yet switched on.** Sections 4 and 5 are the ones to read
before you decide.

---

## 2. What is genuinely ready

| Area | State |
| --- | --- |
| Tenant isolation | Enforced at the database, tested per capability, no known hole |
| Permissions (RBAC) | Enforced at one chokepoint; high-risk actions now require step-up MFA when a tenant turns MFA on |
| Financial correctness | Double-entry enforced; opening balances now reach the general ledger and reconcile exactly |
| Audit trail | Every governed action recorded; sensitive free-text reasons no longer duplicated into the broadly-readable audit log |
| Data migration | Bulk import exists for customers, vendors, items and opening financial balances |
| Production deploy safety | A merge to `main` no longer deploys by itself. Production builds require a recorded go decision matching the exact commit |
| Automated checks | 5,584 unit tests, 236 database test files, 386 migrations — all passing |
| Incident handling | Incidents are recorded, communicated on a defined order, escalated automatically past a threshold, and every message is kept |

---

## 3. Things only you (or someone you hire) can do

These are not agent limitations that a better prompt would solve. Each needs an account
someone owns, a person's signature, or a company's invoice.

`docs/runbooks/human-execution-pack.md` has the exact steps for each. Below is what each one
is and what it costs you to skip it.

<details>
<summary><strong>Superseded 2026-09-03 — the original §3.0, kept because this file is an append-only ledger and a superseded instruction is still evidence of what was believed at the time. Do not act on it; §3.0 below replaces it.</strong></summary>

### 3.0 Point `cargogrid.app` at CargoGrid — and know what it replaces

**Read this one first.** It was found on 2026-08-31 during live verification and it changes what
"launch" means in practice.

**What is true today.** `cargogrid.app` does not show CargoGrid. Typing it into a browser returns
a working page — but it is a *different site*, served by Cloudflare, built with a website
builder. CargoGrid's own health check at `cargogrid.app/api/health` returns "not found", because
CargoGrid is not there. On the hosting side, the domain has never been attached to the CargoGrid
project at all.

**So "deploy" and "publish" are two separate actions, and only one of them is a deploy.**

1. *Deploy* — put the current build live on the hosting platform. It becomes reachable at a
   long `…vercel.app` address. This is the step this session can do, once you say go.
2. *Publish* — make `cargogrid.app` show CargoGrid. This means attaching the domain and changing
   DNS at Cloudflare. **It replaces the site that is on that address right now.** Anyone who
   visits `cargogrid.app` after that change sees CargoGrid instead of the current page.

**Why it is not done.** Step 2 needs access to your Cloudflare DNS and your Vercel domain
settings, neither of which this session has. But access is not really the point: replacing a
live public page is your decision to make, not something that should happen quietly as a
side-effect of clicking deploy.

**Risk if you skip it.** Nothing breaks — you simply have CargoGrid running at an address nobody
knows. The real risk is the opposite one: doing it *without* meaning to. If the current
`cargogrid.app` page is collecting enquiries, running ads, or is what customers have been given,
switching it over without warning takes that away in the same instant. Decide deliberately, and
if the current page matters, keep it somewhere first.

**Tracked as** `ISS-2026-311`.

</details>

### 3.0 Point `app.cargogrid.net` at CargoGrid

**Rewritten 2026-09-03, and the rewrite is the news.** This section previously said that
publishing would *replace* a live public page, because the plan was to put CargoGrid on
`cargogrid.app` — an address already serving a different site built with a website builder. The
owner has since chosen a different address: **CargoGrid's standard domain is
`app.cargogrid.net`**. That removes the whole replacement problem. Nothing public is taken away,
because the app now lives in a different DNS zone entirely from whatever `cargogrid.app` serves.

**What `app.cargogrid.net` is.** The standard address for tenants and for the Supreme Admin
console — the one everybody uses who has not asked for something else. A tenant that wants its
own branded address still requests one through the tenant custom-domain flow inside the app; that
capability is unchanged and fully working, and this rename did not touch it.

**"Deploy" and "publish" are still two separate actions, and only one of them is a deploy.**

1. *Deploy* — put the current build live on the hosting platform. It becomes reachable at a
   long `…vercel.app` address. This session can do that, once you say go.
2. *Publish* — make `app.cargogrid.net` show CargoGrid: attach the domain in Vercel and add one
   DNS record in the `cargogrid.net` zone. Exact steps are in
   `docs/runbooks/human-execution-pack.md` §0.2.

**Why step 2 is not done here.** It needs access to your DNS and your Vercel domain settings,
neither of which this session has.

**Risk if you skip it.** Nothing breaks — you simply have CargoGrid running at an address nobody
knows, and no customer can reach it. Unlike the previous plan, there is no longer a risk of
publishing *by accident* and taking a live page down with it: a brand-new subdomain on a separate
zone replaces nothing.

**One thing this document does not know, said plainly rather than assumed.** Whether the
`cargogrid.net` zone is already under your control, and where its DNS is hosted, has not been
verified from this session — the previous domain was on Cloudflare, but that tells us nothing
about this one. Confirm you can add a record to `cargogrid.net` before scheduling the cutover.

**Tracked as** `ISS-2026-311`.

### 3.0b You have exactly one administrator account — consider a second

**Status: not urgent, and not a defect.** You confirmed you know the password for
`service@cargogrid.net`, so the platform has a reachable administrator. That closes the
launch-blocking question (`ISS-2026-294`).

**What is still true.** That is the *only* administrator identity that exists. No second Supreme
Admin, no other user account at all, and no recovery path anyone has tested.

**Resolved 2026-09-03 — the mismatch this paragraph used to warn about was not a mistake.** It
previously read that the admin address sits on `cargogrid.net` while the product domain was
`cargogrid.app`, and raised the possibility of a typo leaving the mailbox non-existent and a
password reset with nowhere to go. The owner has now set the product's standard domain to
`app.cargogrid.net` (`ISS-2026-311`), so the account and the product are on the same zone after
all and the suspected typo was the *product domain*, not the account. Worth keeping the concrete
check anyway: send a password reset to `service@cargogrid.net` once and confirm it arrives, since
"the domain is right" and "the mailbox is deliverable" are still two different facts.

**Risk if you skip it.** Ordinary bad luck: a forgotten password, a lost password manager, a
laptop that dies. With one account and possibly no working reset mailbox, that is not an
inconvenience — it is the end of your access to your own platform, with no way back in.

**What to do.** Either confirm you can actually receive mail at `service@cargogrid.net` (send
yourself a test), or ask me to create a second Supreme Admin account on an address you control.
It is a single command. I have deliberately not done it on my own: minting a second
top-privilege identity is the kind of thing that should be asked for, never assumed.

### 3.1 Turn on branch protection in GitHub — 10 minutes

**What it is.** Right now anyone with write access to the repository can push straight to the
main branch without review, and nothing stops them.

**Why it is not done.** It is a setting in GitHub's web interface. There is no API in the
tools available here that can change it, so it cannot be scripted from this session.

**Risk if you skip it.** The lowest-effort of the four, and the one with the sharpest teeth. A
single careless push — yours, a contractor's, or an attacker who obtains a token — can put
untested code into the main branch. The production deploy gate (section 2) will still stop
that code reaching customers without a go decision, so this is not a direct route to
production; it is a route to a main branch you can no longer trust.

**Do this one.** It is ten minutes and removes a whole class of accident.

### 3.2 Acceptance testing by real users (UAT) — days, with your people

**What it is.** Somebody who actually does freight forwarding sitting down with CargoGrid and
confirming it does their job.

**Why it is not done.** No agent can accept software on a customer's behalf. Acceptance is a
statement by the person who will live with the result.

**Risk if you skip it.** This is the largest genuine risk on the list, and it is not a
technical one. Every automated test proves the software does what it was *specified* to do.
None of them proves the specification matches how an Indonesian freight forwarder actually
works. The failure mode is not a crash — it is a first customer finding that a workflow they
need every day takes eleven clicks, or does not exist.

**Recommendation.** Do not launch commercially without at least one real operator working
through a real shipment end to end. A friendly first customer counts.

### 3.3 An external penetration test — weeks, and a vendor invoice

**What it is.** A security firm attacking CargoGrid on purpose.

**Why it is not done.** It requires a licensed third party and a contract.

**Risk if you skip it.** The internal security work here is genuinely thorough — dozens of
real vulnerabilities were found and fixed by this build's own reviews, several of them
Critical. But a system reviewing itself has a blind spot by definition. The practical
consequence usually arrives commercially rather than technically: enterprise customers and
insurers ask for a pentest report, and "we have not had one" narrows who will sign with you.

**Recommendation.** Not a launch blocker for early customers. Budget for it before you chase
enterprise accounts.

### 3.4 A second infrastructure provider — a contract, and real money

**What it is.** Everything runs on Supabase. If Supabase has a region-wide outage, CargoGrid
is down until they recover, and you can only wait.

**Why it is not done.** It is a commercial decision with a real recurring cost, not a code
change.

**Risk if you skip it.** You inherit your provider's uptime. For a young product that is
normal and defensible. It stops being defensible in a contract that promises a customer a
specific availability figure — do not sign an availability SLA you cannot meet without this.

**Recommendation.** Accept for now. Revisit when a customer asks for an SLA.

### 3.5 Confirm the tax rate with a tax adviser — an afternoon

**What it is.** The Indonesian PPN rate the system currently uses was seeded as an example. It
has never been confirmed by anyone qualified.

**Why it is not done.** An agent inventing a statutory tax rate would be worse than an agent
declining to.

**Risk if you skip it.** If the rate is wrong, **every invoice computed from it is wrong**,
and that is a tax problem rather than a software bug — the kind that compounds quietly until
someone reconciles a year of invoices.

**This one changed.** It used to require a code release. It no longer does: the tax settings
console (**Admin → Tax settings**) shows every rate, marks any rate that is in force but
unconfirmed with a red banner, and lets a confirmed rate be recorded with its evidence. Your
adviser reads a figure; someone enters it. No release, no migration.

**Do this before you invoice a real customer.**

### 3.6 Rehearse a restore on a real project — half a day

**What it is.** Proving that the backup restore procedure works against a real hosted project,
including file storage and user accounts, not just the database.

**Why it is not done.** Doing it properly means restoring onto real infrastructure, which is
destructive if aimed at the wrong target.

**Risk if you skip it.** You have a documented restore procedure that has never been executed
end to end. Untested backups are the classic operational trap: the moment you discover a
restore does not work is the moment you need it.

**Recommendation.** Do this on a throwaway project before your first paying customer. It is
half a day and it converts a hope into a fact.

### 3.7 Switch on a scheduler — an hour, once

**What it is.** CargoGrid has background jobs — incident escalation, leave accrual, SLA
timers, loyalty expiry — that are written, tested and callable, but nothing runs them on a
timer.

**Why it is not done.** It is deployment wiring (a cron, a scheduled function), and it is one
task for *all* of them rather than one per feature.

**Risk if you skip it.** Anything time-based happens when a person triggers it. The sharpest
case is incident escalation: an unacknowledged alert will not chase anyone until someone runs
the sweep. Everything still *works*; nothing happens *by itself*.

**Recommendation.** Do this at deploy time. It is the difference between a system that watches
itself and one that waits to be asked.

### 3.8 A public status page — built, with one gap left (`ISS-2026-320`)

**What shipped, 2026-09-01.** `/status` — a page customers can load to see whether CargoGrid
is up, when they cannot sign in. It is statically rendered and checks `/api/health`/`/api/ready`
live from the visitor's own browser, so it keeps answering while the application or its
database does not — the outage that matters most, since CargoGrid runs on one backend vendor
with no failover (`ISS-2026-261`).

**What is still deliberately not done, and why.** `/status` shares a host with the
application: if the hosting platform itself goes down, the page never loads either. A page
that survives *that* needs a second host, and standing one up is likely not the purchase it
sounds like. The *previous* domain `cargogrid.app` resolved through Cloudflare's edge
(`server: cloudflare`, live-verified at the time), which made a free Cloudflare Pages page an
obvious ten-minute answer. That reasoning no longer transfers automatically: the product domain
is now `app.cargogrid.net` (`ISS-2026-311`) and **where the `cargogrid.net` zone is hosted has
not been verified from this session**. If it is also on Cloudflare, the same trick applies — a
free Pages site with `status.cargogrid.net` pointed at it by one DNS record. If it is not, most
registrars and hosts offer something equivalent. Confirm against your actual account rather than
taking the old estimate forward. It stays your call because this session holds no DNS credential
of any kind, not because it costs money.

**Risk if you skip the second host.** In the one outage class `/status` cannot cover — the
hosting platform itself down — you reach customers by whatever channel you already have, by
hand. Workable for a handful of customers; it stops scaling, and enterprise buyers ask about
it.

---

## 4. What the remaining 72 items actually are

Not one of them is a crash, a data-loss path, or a tenant-isolation hole. Grouped by what they
mean for you:

**Missing convenience (the largest group).** A capability exists in the database and works,
but has no screen yet, so it is reachable by support rather than self-service. Nothing is
wrong; something is inconvenient.

**Narrower-than-ideal permissions.** A few fields are visible to more people inside a customer
organisation than they ideally would be — for example, the reason someone typed when
cancelling an approval is visible to any colleague in that organisation, not just to admins
(`ISS-2026-305`). No cross-tenant leak; an inside-the-company privacy nuance.

**Missing evidence rather than missing function.** No automated accessibility audit, no
load test at a declared volume, no disaster-recovery timing measurement. The work may well be
fine; nobody has measured it. These become real when a customer asks for the numbers.

**Deliberate scope boundaries.** Features named in the original specification and consciously
not built for the first release — zone/distance vendor pricing, shipment-leg-level vendor
assignment. They are recorded so nobody later mistakes them for oversights.

---

## 5. The honest risks of launching now

Stated plainly, worst first.

1. **Nobody outside this build has used CargoGrid for real work.** Correctness is
   well-established; *fitness* is not. Mitigate with one real operator and one real shipment
   before you charge anyone.
2. **The tax rate is unconfirmed.** Fixable in an afternoon and now a data-entry task. Do it
   before invoicing.
3. **Backups are documented but unrehearsed.** Half a day converts this from hope to fact.
4. **Nothing runs on a timer yet.** Time-based safety nets are manual until a scheduler
   exists.
5. **You inherit Supabase's uptime.** Fine until you sign an availability commitment.
6. **No independent security review.** The internal work is thorough; it is still self-review.

None of these is a reason not to deploy. Several are reasons not to sign an enterprise
contract in the same week.

---

## 6. What "accepted risk" means in the record, and why it is worded that way

Items 3.1–3.8 are recorded as **`ACCEPTED_RISK (OWNER_OVERRIDE)`**, dated, with your
instruction quoted — never as "passed".

That distinction is deliberate and it protects you. *"Penetration test: accepted as a risk by
the owner on 2026-08-30, not performed"* is a position you can defend to an auditor, an
enterprise customer or an insurer. *"Penetration test: passed"*, with no test behind it, is
evidence against you the first time anyone checks.

It costs nothing operationally — the gates stop blocking either way. See `ADR-0027` Part B.

---

## 7. Where to look next

| You want to | Read |
| --- | --- |
| Do the human tasks in section 3 | `docs/runbooks/human-execution-pack.md` |
| See every open item with its full history | `docs/runtime/KNOWN_ISSUES.md` |
| Understand the authority behind this phase | `docs/adr/ADR-0027-owner-authorized-remediation-and-launch.md` |
| Know what happens during an incident | `docs/runbooks/incident-communication.md` |
| Confirm the tax rate | **Admin → Tax settings** in the app |
| Plug in a third-party provider | **Admin → Integrations** in the app |
| See system health and open incidents | **Admin → Monitoring** in the app |

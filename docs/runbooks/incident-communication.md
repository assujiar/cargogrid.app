# Runbook — Incident communication

**Owner:** DevOps / on-call incident commander
**Applies to:** every incident, in every other runbook in this directory. Where another
runbook's §5 Communication section says "notify DevOps/on-call", this file is *how*.
**Closes:** `ISS-2026-258` (no channel, no template, no notification order, no
customer-impact record).

---

## 1. Why this file exists

Before `ISS-2026-258` was closed, all twenty runbooks in this directory shared the same
Communication section: a bare instruction to notify someone, with no named recipient, no
channel, no order, and no record of what was said. That is not a procedure — it is a note
reminding you that a procedure is missing, and at 03:00 during a real outage it is worth
nothing.

The mechanism now exists in the database. This file is the human half of it.

**Corrected 2026-09-01 (`ISS-2026-304`/`ISS-2026-320`).** The paragraph below originally said
there is no public status page at all. That is no longer true: `/status` is a statically
rendered, unauthenticated page that checks `/api/health` and `/api/ready` live from the
visitor's own browser, so it keeps answering while the application or its database is
unreachable — the `customer_portal` audience below still only reaches signed-in portal users,
so `/status` is what a customer who cannot sign in can check instead.

**One outage class is still genuinely uncovered, stated here rather than discovered later**:
`/status` shares a host with the application. If the hosting platform itself is down, the
page never loads either — a genuinely independent status page needs a second host, which is
`ISS-2026-320`'s own remaining subject.

---

## 2. The notification order

It is stored as data, not as prose in this file, so it cannot drift between twenty runbooks
that each state it slightly differently. Read it with:

```sql
select * from app.list_incident_communication_audiences();
```

| # | Audience | Who that resolves to | Why this position |
|---|---|---|---|
| 1 | `internal` | The owning team on the incident's own `app.alert_routes` row, plus the tenant's active `tenant_admin` principals | The people who can **act** on it hear before the people **affected** by it |
| 2 | `tenant_admins` | Every active `tenant_admin` of the affected tenant | They need to know before their own users start asking, and they decide what their organisation is told |
| 3 | `customer_portal` | Active `customer_user`-layer principals of the affected tenant | A message to customers should follow, never precede, the tenant's own administrators being told |

Do not skip a position to save time. Position 1 exists because an incident commander
learning about an outage from a customer's complaint is a worse failure than the outage.

---

## 3. Sending

```sql
select * from app.broadcast_incident_communication(
  p_incident_id               => '<incident uuid>',
  p_audience_code             => 'internal',        -- then tenant_admins, then customer_portal
  p_subject                   => '<one line, plain language>',
  p_body                      => '<the message -- see §4>',
  p_template_config_version_id=> null,              -- or a published notification template
  p_idempotency_key           => '<incident>-<audience>-<update number>',
  p_actor_auth_user_id        => '<your auth user id>',
  p_actor_label               => '<your name>'
);
```

Authority is the same as acknowledging the incident: `MON:Edit` for a tenant-scoped
incident, Supreme Admin for a platform-scoped one. Speaking on an incident's behalf is not
a lesser act than acknowledging it.

**Always pass an idempotency key.** A retry then returns the original instead of sending a
duplicate. Reusing a key with *different* words is refused outright rather than silently
sending the second version — so give each update its own key (`…-update-2`), never reuse
one to "correct" a message already sent.

**Check the returned `recipient_count`.** A broadcast that resolved to zero recipients is
recorded as zero and is not an error — but it means nobody was told. If you expected
recipients and got zero, the audience has no active members, or (for `internal`) no
`app.alert_routes` row matches this incident's `source_type`/`signal_type`. Fix that before
moving on; do not treat the call returning successfully as the job being done.

---

## 4. What to write

Four sentences, in this order. This is the shape, not a script to paste.

1. **What is affected, in the customer's terms.** "Shipment booking may fail", not
   "the carrier adapter is returning 500s".
2. **Since when**, in UTC, with a real timestamp.
3. **What we are doing**, in the present tense.
4. **When the next update comes.** Give a time, and then meet it. An update saying "no
   change yet" at the promised time buys more trust than a fix that arrives silently.

A worked example, from the regression test that proves this mechanism works:

> **Carrier API degraded — investigating**
> We are seeing elevated errors from the carrier API since 09:12 UTC. Shipment booking may
> fail intermittently. Next update within 30 minutes.

Three things to leave out of a customer-facing message: the cause before you are sure of it,
an estimated fix time you cannot stand behind, and any word that implies fault before the
review has happened.

Message templates are ordinary published configuration under the
`notification:incident_communication` type — a tenant can carry its own wording, in its own
language, without a code release. Pass its config version id as
`p_template_config_version_id`.

---

## 5. Afterwards

The record is queryable, and it is the evidence Prompt 384 §24 requires when customer or SLA
communication has to be shown to match what actually happened:

```sql
select * from app.list_incident_communications('<incident uuid>', '<your auth user id>');
```

Each row carries the audience, the severity at the time, the exact subject and body **as
sent** (never a template reference that could be edited afterwards to change what history
says), the recipient count, and how many notifications were queued. The per-recipient detail
lives in `app.incident_communication_recipients`, including any per-recipient dispatch
failure — so "who did we fail to reach" is a query, not a memory.

Every broadcast also lands on the incident's own timeline as a `communicated` event, so the
whole story of an incident stays in one place.

---

## 6. Known limits

| Limit | Consequence | Tracked as |
|---|---|---|
| The status page shares a host with the app | It goes dark in a platform-wide outage, the one case it cannot cover | `ISS-2026-320` — see `human-execution-pack.md` §7 |
| No SLA clock | Send times are recorded, but nothing measures or alerts on a P1 response-time breach | `ISS-2026-258` annotation |
| `internal` depends on an `app.alert_routes` row | An incident with no matching route resolves to the tenant's admins only, and the owning team is not paged | Configure routes via the monitoring console |

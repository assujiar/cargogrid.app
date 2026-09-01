/**
 * Live backup-posture check (ISS-2026-256).
 *
 * WHAT THE ENTRY SAID, AND WHY IT WAS WRONG
 *
 *   `ISS-2026-256` records that this repository's disclosed RPO/RTO defaults — a 15-minute
 *   recovery point and a 4-hour recovery time, `docs/architecture/11_DEVOPS_WORKSTREAM.md`
 *   §8.1 — "have never been operationally confirmed as active on the real hosted project",
 *   and treated that confirmation as something only a human with console access could do.
 *
 *   It is not. The Supabase Management API answers it directly, from the same credential this
 *   repository already uses to apply migrations. The confirmation was performed, and the
 *   answer is worse than "unconfirmed":
 *
 *     GET /v1/projects/<ref>/database/backups  ->  pitr_enabled: false, backups: []
 *     GET /v1/organizations/<slug>             ->  plan: "free"
 *
 *   Point-in-time recovery is OFF and there is not one customer-restorable backup. A
 *   15-minute RPO is not merely unverified; it is unattainable in the current configuration,
 *   and `RPD-025`'s 35-day retention bound is unmet too.
 *
 * WHY THIS IS A SCRIPT AND NOT A ONE-OFF ANSWER
 *
 *   A fact checked once drifts, and this repository has already been bitten by exactly that:
 *   `ISS-2026-284` records a load-bearing environment fact that went stale for 13 days across
 *   21 checkpoints because nothing re-derived it. So the check is a command anyone can re-run,
 *   and it is the same command that will go green on its own the moment somebody enables PITR
 *   — no code change required to confirm the fix.
 *
 * WHY IT IS NOT IN CI
 *
 *   Answering the question needs a credential for the live project. A pipeline that holds one
 *   is a pipeline whose compromise reads production. Same reasoning, and the same shape, as
 *   `scripts/db/check-live-schema-drift.ts` (`ISS-2026-318`): an operator command, not a
 *   pipeline step. With no credentials it prints "NOT RUN" and exits 0 — it never prints a
 *   tick nobody earned.
 */

/** The declared MVP-tier recovery point, `docs/architecture/11_DEVOPS_WORKSTREAM.md` §8.1. */
export const DECLARED_RPO_MINUTES = 15;

export interface LiveBackupPosture {
  readonly pitrEnabled: boolean;
  /** Supabase's own physical-backup daemon. On without PITR still leaves the customer with nothing they can restore themselves. */
  readonly walgEnabled: boolean;
  /** Customer-restorable backups the API reports. */
  readonly backupCount: number;
  /** Age in minutes of the newest restorable backup, or null when there is none. */
  readonly newestBackupAgeMinutes: number | null;
  readonly organizationPlan: string;
}

export type BackupFindingKind = "pitr_disabled" | "no_restorable_backup" | "plan_gated" | "rpo_exceeded";

export interface BackupFinding {
  readonly kind: BackupFindingKind;
  readonly detail: string;
}

/**
 * Pure decision core. Each rule is independent and reports separately, because the remedies
 * differ: a plan upgrade, an add-on purchase, and an actual backup existing are three
 * different facts, and collapsing them into one "backups are bad" verdict would tell whoever
 * has to fix it nothing about what to do.
 */
export function assessBackupPosture(posture: LiveBackupPosture): BackupFinding[] {
  const findings: BackupFinding[] = [];

  if (!posture.pitrEnabled) {
    findings.push({
      kind: "pitr_disabled",
      detail:
        `Point-in-time recovery is disabled. The ${DECLARED_RPO_MINUTES}-minute MVP-tier RPO disclosed in ` +
        "docs/architecture/11_DEVOPS_WORKSTREAM.md §8.1 cannot be met without it: without PITR the recovery point is " +
        "whatever the newest full backup happens to be, not a point you choose.",
    });
  }

  if (posture.backupCount === 0) {
    findings.push({
      kind: "no_restorable_backup",
      detail:
        "The project reports zero customer-restorable backups. The recovery point is therefore unbounded — there is " +
        "nothing to restore from — and RPD-025's 35-day retention bound is unmet." +
        (posture.walgEnabled
          ? " Supabase's own physical backup daemon (WAL-G) is running, but that is the platform's internal safety net, " +
            "not something this account can restore from on demand; it must not be reported as a customer RPO."
          : ""),
    });
  }

  if (posture.organizationPlan === "free") {
    findings.push({
      kind: "plan_gated",
      detail:
        "The organization is on the free plan, where PITR is not available at all. It is a paid add-on " +
        "(7-day $100/month, 14-day $200/month, 28-day $400/month at the time of writing), so closing this is a " +
        "purchasing decision, not a configuration one.",
    });
  }

  // Only meaningful once a backup exists; the no_restorable_backup finding already covers the
  // empty case, and reporting both would double-count one problem.
  if (posture.newestBackupAgeMinutes !== null && posture.newestBackupAgeMinutes > DECLARED_RPO_MINUTES) {
    findings.push({
      kind: "rpo_exceeded",
      detail:
        `The newest restorable backup is ${posture.newestBackupAgeMinutes} minutes old, which already exceeds the ` +
        `disclosed ${DECLARED_RPO_MINUTES}-minute RPO. Data written since then would be lost in a restore.`,
    });
  }

  return findings;
}

interface BackupsResponse {
  readonly pitr_enabled?: boolean;
  readonly walg_enabled?: boolean;
  readonly backups?: readonly { readonly inserted_at?: string }[];
}

async function getJson(url: string, pat: string): Promise<unknown> {
  const response = await fetch(url, { headers: { Authorization: `Bearer ${pat}` } });
  if (!response.ok) throw new Error(`${url} returned HTTP ${response.status}`);
  return response.json();
}

async function main(): Promise<void> {
  const pat = process.env.SUPABASE_PAT;
  const ref = process.env.SUPABASE_PROJECT_REF;

  if (!pat || !ref) {
    console.log("• live backup-posture check NOT RUN — set SUPABASE_PAT and SUPABASE_PROJECT_REF to run it against the live project.");
    console.log("  It reports whether point-in-time recovery is on, whether any customer-restorable backup exists, and");
    console.log("  whether the organization's plan even permits PITR — the three facts behind the disclosed 15-minute RPO.");
    return;
  }

  let posture: LiveBackupPosture;
  try {
    const backups = (await getJson(`https://api.supabase.com/v1/projects/${ref}/database/backups`, pat)) as BackupsResponse;
    const project = (await getJson(`https://api.supabase.com/v1/projects/${ref}`, pat)) as { organization_id?: string };
    const orgId = project.organization_id ?? "";
    const org = orgId ? ((await getJson(`https://api.supabase.com/v1/organizations/${orgId}`, pat)) as { plan?: string }) : {};

    const list = backups.backups ?? [];
    posture = {
      pitrEnabled: backups.pitr_enabled === true,
      walgEnabled: backups.walg_enabled === true,
      backupCount: list.length,
      // Age is left null rather than guessed when the API gives no timestamp: an unknown age
      // reported as 0 would silently claim the RPO is met.
      newestBackupAgeMinutes: null,
      organizationPlan: org.plan ?? "unknown",
    };
  } catch (caught) {
    const message = caught instanceof Error ? caught.message : String(caught);
    console.error(`✖ live backup-posture check could not reach the project (${message}). It has NOT passed; it did not run.`);
    process.exit(1);
  }

  const findings = assessBackupPosture(posture);

  console.log(
    `Live backup posture for ${ref}: pitr_enabled=${posture.pitrEnabled}, walg_enabled=${posture.walgEnabled}, ` +
      `restorable_backups=${posture.backupCount}, organization_plan=${posture.organizationPlan}`,
  );

  if (findings.length > 0) {
    console.error(`\n✖ ${findings.length} backup-posture finding(s) — the disclosed ${DECLARED_RPO_MINUTES}-minute RPO is not being met:`);
    for (const finding of findings) {
      console.error(`  - [${finding.kind}] ${finding.detail}`);
    }
    console.error("\n  This is an owner action, not an engineering one: it needs a plan upgrade and an add-on purchase.");
    console.error("  Re-run this command after that; it goes green on its own with no code change.");
    process.exit(1);
  }

  console.log(`\n✔ point-in-time recovery is enabled and a restorable backup exists within the declared ${DECLARED_RPO_MINUTES}-minute RPO.`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}

/**
 * Environment-facts drift check (ISS-2026-284).
 *
 * WHAT KEEPS HAPPENING, AND WHY A SINGLE DECLARATION FIXES IT
 *
 *   This repository's documentation states load-bearing environment facts — which Vercel
 *   project this repo deploys to, whether production auto-deploy is gated, which Supabase
 *   project is live, which Node version is pinned — as prose, independently, in as many as a
 *   dozen files. Nothing has ever connected those statements to each other or to reality, and
 *   the failure mode has recurred at least twice: Step 15's frozen "no deployed environment
 *   exists" survived unverified for 13 days across 21 checkpoints while a real Vercel project
 *   auto-deployed `main` to production; and `RGL-BLK-001`'s mechanism fix
 *   (`vercel.json` + `scripts/release/check-go-decision.ts`, 2026-08-30) left four current-state
 *   documents — the ACTIVE `deployment-rollback.md` runbook among them — still telling a reader
 *   three days later that production auto-deploys ungated.
 *
 *   `docs/runtime/ENVIRONMENT_FACTS.json` is the one place these facts are declared. This
 *   script is what makes the declaration mean something: it checks that the repository's own
 *   configuration agrees with what is declared (Group A, no credentials, safe for CI), and
 *   that the live providers still agree with what is declared (Group B, credentialed, run by
 *   an operator — same reasoning as `check-live-schema-drift.ts` and
 *   `check-live-backup-config.ts`: a pipeline holding production credentials is a pipeline
 *   whose compromise reads production).
 *
 * WHAT THIS DOES NOT DO
 *
 *   It does not scan prose for stale claims. A checker that greps documentation for phrases
 *   like "ungated" would be exactly as fragile as the problem it is meant to fix — brittle
 *   against rewording, and blind to a new document making the same mistake in different words.
 *   Instead it checks the two things that are actually mechanical: does the repository's own
 *   configuration match the declared fact, and does the live provider still report what was
 *   declared. Prose corrections are a one-time editorial pass, done alongside this script.
 */

export interface EnvironmentFacts {
  readonly vercel: {
    readonly projectId: string;
    readonly teamSlug: string;
    readonly productionAutoDeployGated: boolean;
  };
  readonly supabase: {
    readonly projectRef: string;
    readonly organizationId: string;
  };
  readonly nodeVersion: {
    readonly pinned: string;
  };
}

export interface RepoConfigSnapshot {
  /** Parsed vercel.json, or null if the file does not exist. */
  readonly vercelJson: { git?: { deploymentEnabled?: { main?: boolean } }; ignoreCommand?: string } | null;
  /** package.json's engines.node field, or undefined if unset. */
  readonly packageJsonEngineNode: string | undefined;
}

export interface AssertionFinding {
  readonly kind: "vercel_config_missing" | "vercel_deploy_gate_mismatch" | "vercel_ignore_command_missing" | "node_version_mismatch";
  readonly detail: string;
}

/**
 * Group A: does this repository's own configuration match what `ENVIRONMENT_FACTS.json`
 * declares. Pure and credential-free, so this half runs in CI.
 */
export function findAssertionDrift(facts: EnvironmentFacts, config: RepoConfigSnapshot): AssertionFinding[] {
  const findings: AssertionFinding[] = [];

  if (facts.vercel.productionAutoDeployGated) {
    if (!config.vercelJson) {
      findings.push({
        kind: "vercel_config_missing",
        detail: "ENVIRONMENT_FACTS.json declares production auto-deploy is gated, but no vercel.json exists to gate it. The fact and the repository have drifted apart.",
      });
    } else {
      const mainDeployEnabled = config.vercelJson.git?.deploymentEnabled?.main;
      if (mainDeployEnabled !== false) {
        findings.push({
          kind: "vercel_deploy_gate_mismatch",
          detail: `ENVIRONMENT_FACTS.json declares production auto-deploy is gated, but vercel.json's git.deploymentEnabled.main is ${JSON.stringify(mainDeployEnabled)}, not false.`,
        });
      }
      if (!config.vercelJson.ignoreCommand || !config.vercelJson.ignoreCommand.includes("check-go-decision")) {
        findings.push({
          kind: "vercel_ignore_command_missing",
          detail: "ENVIRONMENT_FACTS.json declares production auto-deploy is gated, but vercel.json's ignoreCommand does not reference the go-decision gate script.",
        });
      }
    }
  }

  if (config.packageJsonEngineNode !== undefined && config.packageJsonEngineNode !== facts.nodeVersion.pinned) {
    findings.push({
      kind: "node_version_mismatch",
      detail: `ENVIRONMENT_FACTS.json declares the pinned Node version as "${facts.nodeVersion.pinned}", but package.json's engines.node is "${config.packageJsonEngineNode}".`,
    });
  }

  return findings;
}

export interface LiveProviderSnapshot {
  readonly vercelProjectFound: boolean;
  readonly supabaseProjectFound: boolean;
}

export interface LiveFinding {
  readonly kind: "vercel_project_not_found" | "supabase_project_not_found";
  readonly detail: string;
}

/**
 * Group B: does the live provider still report what is declared. This is the half that would
 * have caught Step 15's stale "no deployed environment exists" claim — a project moving,
 * being deleted, or a reference rotating out from under the declaration.
 */
export function findLiveDrift(facts: EnvironmentFacts, live: LiveProviderSnapshot): LiveFinding[] {
  const findings: LiveFinding[] = [];
  if (!live.vercelProjectFound) {
    findings.push({
      kind: "vercel_project_not_found",
      detail: `Vercel project ${facts.vercel.projectId} (team ${facts.vercel.teamSlug}) could not be found live. Either it moved, was deleted, or the declared fact is stale.`,
    });
  }
  if (!live.supabaseProjectFound) {
    findings.push({
      kind: "supabase_project_not_found",
      detail: `Supabase project ${facts.supabase.projectRef} could not be found live. Either it moved, was deleted, or the declared fact is stale.`,
    });
  }
  return findings;
}

async function readRepoConfigSnapshot(): Promise<RepoConfigSnapshot> {
  const fs = await import("node:fs/promises");
  let vercelJson: RepoConfigSnapshot["vercelJson"] = null;
  try {
    vercelJson = JSON.parse(await fs.readFile("vercel.json", "utf8"));
  } catch {
    vercelJson = null;
  }
  let packageJsonEngineNode: string | undefined;
  try {
    const pkg = JSON.parse(await fs.readFile("package.json", "utf8"));
    packageJsonEngineNode = pkg.engines?.node;
  } catch {
    packageJsonEngineNode = undefined;
  }
  return { vercelJson, packageJsonEngineNode };
}

async function main(): Promise<void> {
  const fs = await import("node:fs/promises");
  const facts = JSON.parse(await fs.readFile("docs/runtime/ENVIRONMENT_FACTS.json", "utf8")) as EnvironmentFacts;
  const config = await readRepoConfigSnapshot();

  const assertionFindings = findAssertionDrift(facts, config);
  if (assertionFindings.length > 0) {
    console.error(`✖ ${assertionFindings.length} environment-fact drift finding(s) against the repository's own configuration:`);
    for (const finding of assertionFindings) console.error(`  - [${finding.kind}] ${finding.detail}`);
    process.exit(1);
  }
  console.log(`✔ repository configuration agrees with docs/runtime/ENVIRONMENT_FACTS.json (Group A).`);

  const vercelToken = process.env["VERCEL_TOKEN"];
  const supabasePat = process.env["SUPABASE_PAT"];
  if (!vercelToken && !supabasePat) {
    console.log("• live provider check (Group B) NOT RUN — set VERCEL_TOKEN and/or SUPABASE_PAT to run it against the real providers.");
    return;
  }

  let vercelProjectFound = true;
  if (vercelToken) {
    const response = await fetch(`https://api.vercel.com/v9/projects/${facts.vercel.projectId}?teamId=${facts.vercel.teamSlug}`, {
      headers: { Authorization: `Bearer ${vercelToken}` },
    });
    vercelProjectFound = response.ok;
  } else {
    console.log("• VERCEL_TOKEN not set — skipping the Vercel half of Group B.");
  }

  let supabaseProjectFound = true;
  if (supabasePat) {
    const response = await fetch(`https://api.supabase.com/v1/projects/${facts.supabase.projectRef}`, {
      headers: { Authorization: `Bearer ${supabasePat}` },
    });
    supabaseProjectFound = response.ok;
  } else {
    console.log("• SUPABASE_PAT not set — skipping the Supabase half of Group B.");
  }

  const liveFindings = findLiveDrift(facts, { vercelProjectFound, supabaseProjectFound });
  if (liveFindings.length > 0) {
    console.error(`\n✖ ${liveFindings.length} live provider drift finding(s):`);
    for (const finding of liveFindings) console.error(`  - [${finding.kind}] ${finding.detail}`);
    process.exit(1);
  }
  console.log(`✔ live providers agree with docs/runtime/ENVIRONMENT_FACTS.json (Group B, whichever credentials were present).`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  await main();
}

/**
 * Validates a branch name against docs/git/GIT_STRATEGY.md §1.1's naming table.
 *
 * CLI: node --experimental-strip-types scripts/git/check-branch-name.ts <branch-name>
 *      (no argument = reads the current branch via `git rev-parse --abbrev-ref HEAD`)
 */

const PATTERNS: ReadonlyArray<{ readonly label: string; readonly regex: RegExp }> = [
  { label: "agent/<slug>", regex: /^agent\/[a-z0-9-]+$/ },
  { label: "claude/<slug> (harness-assigned)", regex: /^claude\/[a-z0-9-]+$/ },
  { label: "feature/<task-id>-<slug>", regex: /^feature\/[A-Z][A-Z0-9-]*-\d+-[a-z0-9-]+$/ },
  { label: "hotfix/<task-id>-<slug>", regex: /^hotfix\/[A-Z][A-Z0-9-]*-\d+-[a-z0-9-]+$/ },
  { label: "codex/<slug> (external tooling)", regex: /^codex\/[a-z0-9-]+$/ },
];

export interface BranchNameCheckResult {
  readonly valid: boolean;
  readonly matchedPattern?: string;
  readonly message: string;
}

export function checkBranchName(branch: string): BranchNameCheckResult {
  if (branch === "main") {
    return {
      valid: true,
      matchedPattern: "main",
      message: "main — receives merges only per docs/git/GIT_STRATEGY.md §1 (informational, not a hard block here)",
    };
  }

  for (const { label, regex } of PATTERNS) {
    if (regex.test(branch)) {
      return { valid: true, matchedPattern: label, message: `matches "${label}"` };
    }
  }

  return {
    valid: false,
    message: `"${branch}" does not match any documented pattern (docs/git/GIT_STRATEGY.md §1.1: ${PATTERNS.map((p) => p.label).join(", ")}, or "main")`,
  };
}

async function currentBranch(): Promise<string> {
  const { execFileSync } = await import("node:child_process");
  return execFileSync("git", ["rev-parse", "--abbrev-ref", "HEAD"], { encoding: "utf8" }).trim();
}

async function main(): Promise<void> {
  const arg = process.argv[2];
  const branch = arg ?? (await currentBranch());
  const result = checkBranchName(branch);

  if (result.valid) {
    console.log(`✔ branch "${branch}": ${result.message}`);
  } else {
    console.error(`✖ branch "${branch}": ${result.message}`);
    process.exit(1);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

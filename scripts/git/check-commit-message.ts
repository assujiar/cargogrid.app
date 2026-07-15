/**
 * Validates a commit message against docs/git/GIT_STRATEGY.md §1.2's convention:
 *
 *   agent: <verb> <description> (<task-id>, Prompt <n>)
 *
 * The task-id/Prompt-number suffix is required for a Phase-0-style checkpoint
 * commit but optional for a short incidental commit (e.g. a typo fix) —
 * flagged as a warning, not a hard failure, since not every real commit in
 * this repository's history is a full checkpoint (see docs/build-log/phase-00/PH0-87.md
 * §6 for real examples checked against this validator).
 *
 * CLI: node --experimental-strip-types scripts/git/check-commit-message.ts <path-to-message-file>
 *      node --experimental-strip-types scripts/git/check-commit-message.ts --message "agent: ..."
 */

const SUBJECT_LINE_PATTERN = /^agent: [a-z]+ .+$/;
const TASK_SUFFIX_PATTERN = /\([A-Z][A-Z0-9-]*-\d+.*Prompt \d+\)/;
const KNOWN_VERBS = ["complete", "implement", "reconcile", "record", "update", "close", "revert", "add", "fix"];

export interface CommitMessageCheckResult {
  readonly valid: boolean;
  readonly errors: readonly string[];
  readonly warnings: readonly string[];
}

export function checkCommitMessage(message: string): CommitMessageCheckResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const trimmed = message.trim();

  if (trimmed.length === 0) {
    return { valid: false, errors: ["commit message is empty"], warnings: [] };
  }

  const subjectLine = (trimmed.split("\n")[0] ?? "").trim();

  if (!SUBJECT_LINE_PATTERN.test(subjectLine)) {
    errors.push(`subject line must match "agent: <verb> <description>" — got: "${subjectLine}"`);
  } else {
    const verb = subjectLine.slice("agent: ".length).split(" ")[0] ?? "";
    if (!KNOWN_VERBS.includes(verb)) {
      warnings.push(`verb "${verb}" is not in the documented list (${KNOWN_VERBS.join(", ")}) — allowed, but confirm it's imperative and accurate`);
    }
  }

  if (!TASK_SUFFIX_PATTERN.test(trimmed)) {
    warnings.push('no "(<TASK-ID>, Prompt <n>)" reference found anywhere in the message — required for a checkpoint commit, optional for an incidental fix (docs/git/GIT_STRATEGY.md §1.2)');
  }

  if (subjectLine.length > 100) {
    warnings.push(`subject line is ${subjectLine.length} chars — consider keeping it under ~72-100 for readability`);
  }

  return { valid: errors.length === 0, errors, warnings };
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  let message: string;

  if (args[0] === "--message") {
    message = args[1] ?? "";
  } else if (args[0]) {
    const fs = await import("node:fs/promises");
    message = await fs.readFile(args[0], "utf8");
  } else {
    console.error("Usage: check-commit-message.ts <path-to-message-file> | --message \"...\"");
    process.exit(2);
  }

  const result = checkCommitMessage(message);
  for (const w of result.warnings) console.warn(`⚠ ${w}`);
  for (const e of result.errors) console.error(`✖ ${e}`);

  if (!result.valid) {
    process.exit(1);
  }
  console.log("✔ commit message passes docs/git/GIT_STRATEGY.md §1.2");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

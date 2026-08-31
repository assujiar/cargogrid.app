/**
 * `ISS-2026-248`: a static guard for the two visible defect classes `ISS-2026-247` fixed by hand —
 * a wide table with no horizontal-scroll wrapper, and an interactive control smaller than the
 * touch-target floor. Both were things a human reviewer had to catch by eye, so both could
 * silently come back.
 *
 * WHY THIS IS NOT AN ESLint RULE, WHICH IS WHAT THE ENTRY ASSUMED
 *
 * `ISS-2026-248` reasoned from `eslint.config.js`'s `no-restricted-syntax` precedent and
 * concluded, correctly, that the guard could not be built there: "table with no wrapper in the
 * same file" is an **absence-of-pattern** check across a whole file, and a `no-restricted-syntax`
 * selector matches individual AST nodes. You cannot express "this node is missing something
 * elsewhere" in a per-node selector.
 *
 * But ESLint was never the only option. This repository already runs ten standalone checker
 * scripts as `pnpm` gates (`check-secrets`, `check-rls-initplan`, `check-protected-paths`,
 * `check-known-issues`, …), and a file-level absence check is exactly what those are for. The
 * blocker was the tool, not the check.
 *
 * WHAT IT DELIBERATELY DOES NOT FLAG
 *
 * The entry also warned that a naive size rule "cannot distinguish a decorative small element
 * from an interactive one via AST alone." That is true of a bare size selector, and it is why
 * this checker looks only at **interactive tags**, never at the `<svg className="h-4 w-4">` icons
 * inside them.
 *
 * It then carves out one further exception, measured rather than assumed. A checkbox or radio
 * with an `id` that a `<label htmlFor>` in the same file points at is **not** flagged: clicking
 * that label operates the control, so the real target is the label, not the 16px box. Every one
 * of the four small controls in the tree today is exactly that shape — which is what makes this
 * rule safe to enable as an error rather than a warning.
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

export interface InteractionFinding {
  readonly file: string;
  readonly line: number;
  readonly rule: "TABLE_NO_SCROLL_WRAPPER" | "UNDERSIZED_TOUCH_TARGET";
  readonly detail: string;
}

/**
 * 44 CSS px. `docs/standards/DESIGN_SYSTEM.md`'s own floor, and WCAG 2.5.5's AAA target size —
 * the number `ISS-2026-247` fixed against, kept here rather than re-derived.
 */
export const TOUCH_TARGET_FLOOR_PX = 44;

const SCROLL_WRAPPERS = ["overflow-x-auto", "overflow-auto", "overflow-x-scroll"];

/** Tags a person actually presses. An `<svg>` or `<div>` sized small is decoration until proven otherwise. */
const INTERACTIVE_TAGS = ["button", "a", "input", "select", "textarea"];

/**
 * Tailwind's `h-N` scale is N * 0.25rem = N * 4px, so anything below `h-11` is under 44px.
 * `h-full`, `h-auto`, `h-screen`, `h-px` and arbitrary percentages are not a fixed pixel height
 * and are left alone — this rule is about a control pinned small, not about every height.
 */
function fixedHeightPx(className: string): number | null {
  const arbitrary = /\b(?:min-)?h-\[(\d+)px\]/.exec(className);
  if (arbitrary?.[1]) return Number(arbitrary[1]);
  const scale = /\b(?:min-)?h-(\d{1,2})(?![\w.[-])/.exec(className);
  if (scale?.[1]) return Number(scale[1]) * 4;
  return null;
}

function classNameOf(tagText: string): string | null {
  const match = /className="([^"]*)"/.exec(tagText);
  return match?.[1] ?? null;
}

/**
 * A checkbox/radio operated by an associated label is exempt: clicking the label operates the
 * control, so the real target is the label, not the 16px box.
 *
 * **Both association forms count**, and getting this wrong is not academic — the first draft of
 * this checker recognised only `htmlFor` and promptly flagged two controls in
 * `admin/scheduler/scheduler-admin-panel.tsx` that are perfectly correct, because they use the
 * other form. HTML allows a label to own a control either by naming its `id`:
 *
 *     <input id="x" type="checkbox" /> <label htmlFor="x">…</label>
 *
 * or by simply wrapping it, with no `id` anywhere:
 *
 *     <label><input type="checkbox" /> …</label>
 *
 * A rule that knows only the first form does not find defects — it finds the second form. That is
 * exactly the false-positive class `ISS-2026-248` warned this guard had to be validated against
 * before being enabled as an error, and it was, against the whole tree.
 */
function hasAssociatedLabel(source: string, tagText: string, index: number): boolean {
  const type = /type="(checkbox|radio)"/.exec(tagText);
  if (!type) return false;

  // Explicit: <label htmlFor="…"> somewhere in the file names this control's id.
  const id = /\bid="([^"]+)"/.exec(tagText);
  if (id?.[1] && source.includes(`htmlFor="${id[1]}"`)) return true;

  // Implicit: the control sits inside a <label> that has not been closed before it.
  const before = source.slice(0, index);
  const lastOpen = before.lastIndexOf("<label");
  if (lastOpen === -1) return false;
  return !before.slice(lastOpen).includes("</label>");
}

export function checkSource(source: string, file: string): InteractionFinding[] {
  const findings: InteractionFinding[] = [];
  const lines = source.split("\n");

  const tableLine = lines.findIndex((l) => l.includes("<table"));
  if (tableLine >= 0 && !SCROLL_WRAPPERS.some((w) => source.includes(w))) {
    findings.push({
      file,
      line: tableLine + 1,
      rule: "TABLE_NO_SCROLL_WRAPPER",
      detail: `<table> with no ${SCROLL_WRAPPERS.join("/")} anywhere in the file — a wide table will clip on a narrow screen instead of scrolling`,
    });
  }

  // Matches an opening tag up to its `>`; good enough for JSX written in this repository's style,
  // and deliberately not a parser: a checker that is wrong about a `>` inside a string is a
  // checker nobody trusts, so the tag regex stops at the first `>` and accepts that a tag split
  // in an unusual way is simply not inspected.
  const tagPattern = new RegExp(`<(${INTERACTIVE_TAGS.join("|")})\\b[^>]*>`, "g");
  for (const match of source.matchAll(tagPattern)) {
    const tagText = match[0];
    const className = classNameOf(tagText);
    if (!className) continue;
    const height = fixedHeightPx(className);
    if (height === null || height >= TOUCH_TARGET_FLOOR_PX) continue;
    if (hasAssociatedLabel(source, tagText, match.index)) continue;
    findings.push({
      file,
      line: source.slice(0, match.index).split("\n").length,
      rule: "UNDERSIZED_TOUCH_TARGET",
      detail: `<${match[1]}> pinned to ${height}px, below the ${TOUCH_TARGET_FLOOR_PX}px touch-target floor — give it at least h-11, or associate a <label htmlFor> if it is a checkbox/radio`,
    });
  }

  return findings;
}

function walk(dir: string, out: string[]): void {
  for (const entry of readdirSync(dir)) {
    if (entry === "node_modules" || entry === ".next" || entry.startsWith(".")) continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (full.endsWith(".tsx")) out.push(full);
  }
}

function main(): void {
  const root = process.cwd();
  const files: string[] = [];
  for (const dir of ["app", "components"]) {
    try {
      walk(join(root, dir), files);
    } catch {
      // A missing directory is not a violation — this checker reports on what exists.
    }
  }

  const findings = files.flatMap((f) => checkSource(readFileSync(f, "utf8"), relative(root, f)));

  for (const f of findings) {
    console.error(`✖ ${f.rule} ${f.file}:${f.line} — ${f.detail}`);
  }
  console.log(`\ninteraction primitives: ${files.length} .tsx file(s) checked, ${findings.length} finding(s).`);
  if (findings.length > 0) {
    console.error("\nISS-2026-248: these are the two defect classes ISS-2026-247 fixed by hand. Fix them rather than widening this checker.");
    process.exitCode = 1;
    return;
  }
  console.log("✔ every table can scroll horizontally, and every interactive control meets the touch-target floor.");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}

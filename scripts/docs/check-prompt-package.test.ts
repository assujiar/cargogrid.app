import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import {
  checkPromptPackage,
  classifyNextSection,
  parseSections,
  parseManifestRows,
  REQUIRED_PROMPT_HEADINGS,
  REQUIRED_CONTROL_FILES,
  hasIndentedBody,
  KNOWN_TEMPLATE_VARIANT_FILES,
  VERSION_BEARING_CONTROL_FILES,
  EXPECTED_PACKAGE_VERSION,
} from "./check-prompt-package.ts";

/**
 * A validator that only ever reports "pass" is indistinguishable from one that does nothing.
 * Every check below is pinned twice: once against a well-formed synthetic package, and once
 * against a package with exactly one defect injected, asserting the specific finding code.
 */

/** Builds a minimal but structurally valid package in a temp dir, then applies mutations. */
function buildPackage(mutate?: (files: Map<string, string>) => void): string {
  const files = new Map<string, string>();

  const structuredPrompt = (num: number, promptId: string, docId: string, nextBody: string): string => {
    const head = `# Prompt ${num} - Synthetic\n\n**Prompt ID:** \`${promptId}\`  \n**Package document:** \`${docId}\`  \n**Version:** \`0.18.0\`  \n`;
    const body = REQUIRED_PROMPT_HEADINGS.map((h) =>
      h === "36. Next eligible prompt" ? `## ${h}\n\n${nextBody}\n` : `## ${h}\n\nSynthetic content for ${h}.\n`,
    ).join("\n");
    return `${head}\n${body}`;
  };

  for (const cf of REQUIRED_CONTROL_FILES) {
    const needsVersion = VERSION_BEARING_CONTROL_FILES.includes(cf);
    files.set(cf, `# Control\n\n${needsVersion ? `**Package version:** \`${EXPECTED_PACKAGE_VERSION}\`\n` : "Body.\n"}`);
  }
  files.set("START_HERE.md", `# Start Here\n\n**Package version:** \`${EXPECTED_PACKAGE_VERSION}\`\n`);

  files.set(
    "17-final-validation/415_A_PROMPT.md",
    structuredPrompt(415, "CG-S17-FPV-002", "CG-AABPP-FPV-415", "If this task is `VERIFIED`, continue only to `FPV-416`."),
  );
  files.set(
    "17-final-validation/416_B_PROMPT.md",
    structuredPrompt(416, "CG-S17-FPV-003", "CG-AABPP-FPV-416", "If this task is `VERIFIED`, continue only to `FPV-417`."),
  );
  files.set(
    "17-final-validation/417_C_PROMPT.md",
    structuredPrompt(417, "CG-S17-FPV-004", "CG-AABPP-FPV-417", "Terminal. No further prompt."),
  );

  mutate?.(files);

  // The manifest is derived last so mutations to the file set stay consistent by default;
  // a test that wants a manifest defect injects it through the `__manifest__` sentinel.
  const override = files.get("__manifest__");
  files.delete("__manifest__");
  const rows = [...files.keys()]
    .filter((p) => p !== "00-control/07_PROMPT_PACKAGE_MANIFEST.md")
    .sort()
    .map((p, i) => `| M-${String(i).padStart(3, "0")} | \`${p}\` | purpose | 0.18.0 | \`FINAL_FOR_STEP\` | inputs |`);
  rows.push(`| M-999 | \`00-control/07_PROMPT_PACKAGE_MANIFEST.md\` | manifest | 0.18.0 | \`FINAL_FOR_STEP\` | self |`);
  files.set(
    "00-control/07_PROMPT_PACKAGE_MANIFEST.md",
    `# Manifest\n\n**Package version:** \`${EXPECTED_PACKAGE_VERSION}\`\n\n| Manifest item | Relative path | Purpose | Version | Status | Inputs |\n|---|---|---|---|---|---|\n${override ?? rows.join("\n")}\n`,
  );

  const root = mkdtempSync(join(tmpdir(), "cg-pkg-"));
  for (const [p, content] of files) {
    mkdirSync(dirname(join(root, p)), { recursive: true });
    writeFileSync(join(root, p), content);
  }
  return root;
}

function codesFrom(root: string): string[] {
  try {
    return checkPromptPackage(root).findings.map((f) => f.code);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

describe("checkPromptPackage — the happy path", () => {
  test("a well-formed synthetic package produces no finding at all", () => {
    const root = buildPackage();
    try {
      const { findings, stats } = checkPromptPackage(root);
      assert.deepEqual(findings, [], `expected clean, got ${JSON.stringify(findings, null, 2)}`);
      assert.equal(stats.structuredPromptCount, 3);
      assert.equal(stats.explicitNextEdges, 2, "415→416 and 416→417");
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});

describe("checkPromptPackage — each check actually catches its defect", () => {
  test("DUPLICATE_PROMPT_ID: two files claiming the same Prompt ID", () => {
    const codes = codesFrom(
      buildPackage((f) => {
        const dup = f.get("17-final-validation/416_B_PROMPT.md")!.replace("CG-S17-FPV-003", "CG-S17-FPV-002");
        f.set("17-final-validation/416_B_PROMPT.md", dup);
      }),
    );
    assert.ok(codes.includes("DUPLICATE_PROMPT_ID"), `got ${codes.join(", ")}`);
  });

  test("DUPLICATE_DOCUMENT_ID: two files claiming the same package document ID", () => {
    const codes = codesFrom(
      buildPackage((f) => {
        const dup = f.get("17-final-validation/416_B_PROMPT.md")!.replace("CG-AABPP-FPV-416", "CG-AABPP-FPV-415");
        f.set("17-final-validation/416_B_PROMPT.md", dup);
      }),
    );
    assert.ok(codes.includes("DUPLICATE_DOCUMENT_ID"), `got ${codes.join(", ")}`);
  });

  test("MANIFEST_PATH_MISSING: a manifest row pointing at a file that does not exist", () => {
    const codes = codesFrom(
      buildPackage((f) => {
        f.set("__manifest__", "| M-001 | `17-final-validation/999_GONE.md` | purpose | 0.18.0 | `FINAL_FOR_STEP` | x |");
      }),
    );
    assert.ok(codes.includes("MANIFEST_PATH_MISSING"), `got ${codes.join(", ")}`);
  });

  test("FILE_NOT_IN_MANIFEST: a file present on disk with no manifest row", () => {
    const codes = codesFrom(
      buildPackage((f) => {
        f.set("__manifest__", "| M-001 | `START_HERE.md` | purpose | 0.18.0 | `FINAL_FOR_STEP` | x |");
      }),
    );
    assert.ok(codes.includes("FILE_NOT_IN_MANIFEST"), `got ${codes.join(", ")}`);
  });

  test("DUPLICATE_MANIFEST_ID and DUPLICATE_MANIFEST_PATH", () => {
    const codes = codesFrom(
      buildPackage((f) => {
        f.set(
          "__manifest__",
          "| M-001 | `START_HERE.md` | purpose | 0.18.0 | `FINAL_FOR_STEP` | x |\n" +
            "| M-001 | `START_HERE.md` | purpose | 0.18.0 | `FINAL_FOR_STEP` | x |",
        );
      }),
    );
    assert.ok(codes.includes("DUPLICATE_MANIFEST_ID"), `got ${codes.join(", ")}`);
    assert.ok(codes.includes("DUPLICATE_MANIFEST_PATH"), `got ${codes.join(", ")}`);
  });

  test("HEADING_ORDER: two sections transposed, with everything still present", () => {
    // The subtle case -- a count-only check would pass this, because all 36 headings exist.
    const codes = codesFrom(
      buildPackage((f) => {
        const original = f.get("17-final-validation/415_A_PROMPT.md")!;
        const swapped = original
          .replace("## 4. Objective", "## __TMP__")
          .replace("## 5. Business value", "## 4. Objective")
          .replace("## __TMP__", "## 5. Business value");
        f.set("17-final-validation/415_A_PROMPT.md", swapped);
      }),
    );
    assert.ok(codes.includes("HEADING_ORDER"), `got ${codes.join(", ")}`);
    assert.ok(!codes.includes("HEADING_COUNT"), "count is unchanged — order is the defect");
  });

  test("HEADING_COUNT: a section removed outright", () => {
    const codes = codesFrom(
      buildPackage((f) => {
        const original = f.get("17-final-validation/415_A_PROMPT.md")!;
        f.set(
          "17-final-validation/415_A_PROMPT.md",
          original.replace("## 29. Regression tests\n\nSynthetic content for 29. Regression tests.\n", ""),
        );
      }),
    );
    assert.ok(codes.includes("HEADING_COUNT"), `got ${codes.join(", ")}`);
  });

  test("EMPTY_SECTION: a heading present but with no body — the §24 'no-acceptance' shape", () => {
    const codes = codesFrom(
      buildPackage((f) => {
        const original = f.get("17-final-validation/415_A_PROMPT.md")!;
        f.set(
          "17-final-validation/415_A_PROMPT.md",
          original.replace("## 33. Acceptance criteria\n\nSynthetic content for 33. Acceptance criteria.\n", "## 33. Acceptance criteria\n\n"),
        );
      }),
    );
    assert.ok(codes.includes("EMPTY_SECTION"), `got ${codes.join(", ")}`);
  });

  test("NEXT_TARGET_MISSING: §36 naming a prompt that has no file", () => {
    const codes = codesFrom(
      buildPackage((f) => {
        const original = f.get("17-final-validation/415_A_PROMPT.md")!;
        f.set("17-final-validation/415_A_PROMPT.md", original.replace("`FPV-416`", "`FPV-418`"));
      }),
    );
    assert.ok(codes.includes("NEXT_TARGET_MISSING"), `got ${codes.join(", ")}`);
  });

  test("NEXT_SELF_LOOP and NEXT_BACKWARD_EDGE: the two shapes a cycle takes", () => {
    const selfLoop = codesFrom(
      buildPackage((f) => {
        const original = f.get("17-final-validation/415_A_PROMPT.md")!;
        f.set("17-final-validation/415_A_PROMPT.md", original.replace("`FPV-416`", "`FPV-415`"));
      }),
    );
    assert.ok(selfLoop.includes("NEXT_SELF_LOOP"), `got ${selfLoop.join(", ")}`);

    const backward = codesFrom(
      buildPackage((f) => {
        const original = f.get("17-final-validation/416_B_PROMPT.md")!;
        f.set("17-final-validation/416_B_PROMPT.md", original.replace("`FPV-417`", "`FPV-415`"));
      }),
    );
    assert.ok(backward.includes("NEXT_BACKWARD_EDGE"), `got ${backward.join(", ")}`);
  });

  test("MISSING_CONTROL_FILE and MISSING_START_HERE", () => {
    const noControl = codesFrom(buildPackage((f) => f.delete("00-control/04_CONFLICT_REGISTER.md")));
    assert.ok(noControl.includes("MISSING_CONTROL_FILE"), `got ${noControl.join(", ")}`);

    const noStart = codesFrom(buildPackage((f) => f.delete("START_HERE.md")));
    assert.ok(noStart.includes("MISSING_START_HERE"), `got ${noStart.join(", ")}`);
  });

  test("CONTROL_FILE_VERSION_MISMATCH: a control file declaring a stale package version", () => {
    const codes = codesFrom(
      buildPackage((f) => {
        f.set("START_HERE.md", "# Start Here\n\n**Package version:** `0.17.0-step16`\n");
      }),
    );
    assert.ok(codes.includes("CONTROL_FILE_VERSION_MISMATCH"), `got ${codes.join(", ")}`);
  });

  test("EMPTY_FILE: an empty placeholder, which manifest §1 rule 4 forbids", () => {
    const codes = codesFrom(buildPackage((f) => f.set("17-final-validation/417_C_PROMPT.md", "")));
    assert.ok(codes.includes("EMPTY_FILE"), `got ${codes.join(", ")}`);
  });
});

describe("classifyNextSection", () => {
  test("separates a task ID from a prompt number using the step's own range", () => {
    // The real Phase 2 shape: CG-S7-COM-011 is the task sequence, COM-152 the prompt number.
    // Without the range, `COM-011` reads as a backward edge to prompt 11 and manufactures a
    // false cycle -- this is the exact defect this check was rewritten to eliminate.
    const body = "`CG-S7-COM-011` / `COM-152` only after acceptance/dependencies pass; otherwise output the exact blocked/failed/partial resume prompt.";
    const ranged = classifyNextSection(body, [140, 164]);
    assert.equal(ranged.kind, "EXPLICIT");
    assert.deepEqual(ranged.targets, [152], "only the in-range number is a successor");

    const unranged = classifyNextSection(body);
    assert.ok(unranged.targets.includes(11), "without a range the task ID is indistinguishable — the reason the range exists");
  });

  test("accepts the first prompt of the next step as a successor", () => {
    const ref = classifyNextSection("`CG-S7-COM-024` / `COM-165` only after acceptance.", [140, 164]);
    assert.deepEqual(ref.targets, [165]);
  });

  test("classifies template placeholders, index delegation, and terminals", () => {
    assert.equal(classifyNextSection("`{{NEXT_ELIGIBLE_PROMPT_ID}}` only when acceptance passes.").kind, "TEMPLATE");
    assert.equal(
      classifyNextSection("Only the execution index may release the next dependency-clean IAE prompt after this task is `VERIFIED`.").kind,
      "INDEX_DELEGATED",
    );
    assert.equal(classifyNextSection("This is the final prompt. Stop.").kind, "TERMINAL");
  });

  test("does not read a prohibition as a successor edge", () => {
    // "only Prompt 367 may do so" forbids something; it does not name what runs next.
    const ref = classifyNextSection(
      "Only the execution index may release the next dependency-clean IAE prompt after this task is `VERIFIED`. Do not set the final Phase 9 closure flag; only Prompt 367 may do so.",
      [329, 367],
    );
    assert.equal(ref.kind, "INDEX_DELEGATED");
    assert.deepEqual(ref.targets, []);
  });
});

describe("indented bodies — the defect that hid from the first version of this script", () => {
  test("hasIndentedBody distinguishes an indented body from a normal one", () => {
    assert.equal(hasIndentedBody("# T\n\n    ## 1. Prompt ID\n\n    body\n"), true);
    assert.equal(hasIndentedBody("# T\n\n## 1. Prompt ID\n\nbody\n"), false);
    // A fenced code block that happens to contain a heading-like line is not an indented body,
    // because the document still has real top-level headings.
    assert.equal(hasIndentedBody("# T\n\n## 1. Prompt ID\n\n    ## 2. Not a heading\n"), false);
  });

  test("parseSections still finds the structure inside an indented body", () => {
    // One defect must not hide every other defect in the same file.
    const sections = parseSections("# T\n\n    ## 1. Prompt ID\n\n    alpha\n\n    ## 2. Parent phase\n\n    beta\n");
    assert.deepEqual(sections.map((s) => s.heading), ["1. Prompt ID", "2. Parent phase"]);
  });

  test("an indented body is ERROR when unknown, WARN when pinned as a disclosed variant", () => {
    const indent = (content: string): string => content.split("\n").map((l) => (l ? `    ${l}` : l)).join("\n");

    const unknown = buildPackage((f) => {
      f.set("17-final-validation/415_A_PROMPT.md", indent(f.get("17-final-validation/415_A_PROMPT.md")!));
    });
    try {
      const findings = checkPromptPackage(unknown).findings.filter((x) => x.code === "INDENTED_BODY");
      assert.equal(findings.length, 1);
      assert.equal(findings[0]?.severity, "ERROR", "a NEW indented file must fail the gate");
    } finally {
      rmSync(unknown, { recursive: true, force: true });
    }
  });

  test("no prompt in the package has an indented body, and no exception is available to one that does", () => {
    // Was: "the pinned allowlist is exhaustive and matches the real package exactly", asserting
    // the 14 known-indented files were disclosed as WARN. Revision 0.19.0 (ADR-0028) fixed all
    // 14 (FPV-F003), so the assertion inverts: there must now be NO indented body anywhere, and
    // -- the half that matters more -- no allowlist entry left that could soften a new one.
    const { findings, stats } = checkPromptPackage("docs/ai-agent-build-prompt-package");
    const indented = findings.filter((f) => f.code === "INDENTED_BODY");
    assert.deepEqual(indented.map((f) => f.path), [], "no prompt may render as a single code block");
    assert.equal(stats.indentedBodyCount, 0);
    assert.deepEqual(
      [...KNOWN_TEMPLATE_VARIANT_FILES],
      [],
      "the allowlist must stay empty — an exception that outlives its reason is where the next defect hides",
    );
  });

  test("a hypothetical indented file would now be an ERROR, not a WARN", () => {
    // The allowlist being empty is only meaningful if the un-allowlisted path is blocking.
    // Asserted on the classifier directly rather than by mutating the real package.
    assert.equal(KNOWN_TEMPLATE_VARIANT_FILES.includes("anything/at/all.md"), false);
    assert.ok(hasIndentedBody("    ## 1. Prompt ID\n    Some body\n"), "the detector still detects");
  });
});

describe("classifyNextSection — preconditions and prohibitions are not successors", () => {
  test("\"after X is verified\" names a precondition, not the next prompt", () => {
    const ref = classifyNextSection(
      "Only the execution index may release ATW-247 after ATW-246 is verified. Prompt 248 alone may close Phase 5.",
      [219, 248],
    );
    assert.deepEqual(ref.targets, [247], "246 is the precondition, 248 is a prohibition");
  });

  test("the same clause with words in between is still a precondition", () => {
    // The real Phase 5 wording that survived the first fix and had to be generalized.
    const ref = classifyNextSection(
      "Only the execution index may release ATW-227 or another dependency-clean task after all required ATW-226 child tasks are verified. Prompt 248 alone may close Phase 5.",
      [219, 248],
    );
    assert.deepEqual(ref.targets, [227]);
  });

  test("\"Prompt N alone may close\" is a prohibition", () => {
    const ref = classifyNextSection("Only the execution index may release ATW-244 or another dependency-clean task. Prompt 248 alone may close Phase 5.", [219, 248]);
    assert.deepEqual(ref.targets, [244]);
  });
});

describe("parsers", () => {
  test("parseSections keeps document order and captures bodies", () => {
    const sections = parseSections("# Title\n\n## 1. A\n\nalpha\n\n## 2. B\n\nbeta\n");
    assert.deepEqual(sections.map((s) => s.heading), ["1. A", "2. B"]);
    assert.equal(sections[0]?.body.trim(), "alpha");
  });

  test("parseManifestRows reads id and path, ignoring the header and separator rows", () => {
    const rows = parseManifestRows(
      "| Manifest item | Relative path |\n|---|---|\n| M-000 | `00-control/00_PACKAGE_README.md` | x |\n| M-001 | `START_HERE.md` | y |\n",
    );
    assert.deepEqual(rows, [
      { id: "M-000", path: "00-control/00_PACKAGE_README.md" },
      { id: "M-001", path: "START_HERE.md" },
    ]);
  });
});

describe("the real package", () => {
  test("docs/ai-agent-build-prompt-package/ passes with zero ERROR findings", () => {
    const { findings, stats } = checkPromptPackage("docs/ai-agent-build-prompt-package");
    const errors = findings.filter((f) => f.severity === "ERROR");
    assert.deepEqual(errors, [], `real package has structural errors: ${JSON.stringify(errors, null, 2)}`);

    // Pin the shape of the package so silent drift is a test failure, not a surprise later.
    //
    // Moved at package revision 0.19.0-step17-r1 (ADR-0028). The previous pin was
    // 430 / 430 / 338; the +1 is `431_TENANT_MERGE_SPLIT_PROMPT.md`, authored to close
    // FPV-F001 (`RPD-020` carried by no prompt anywhere). The pin is not relaxed — it is
    // moved to the new documented value, which is the whole point of pinning: a change to
    // these numbers must be someone's deliberate act, recorded, never a silent drift.
    assert.equal(stats.fileCount, 431);
    assert.equal(stats.manifestRowCount, 431);
    assert.equal(stats.structuredPromptCount, 339, "338 + the tenant merge/split prompt closing FPV-F001");

    // FPV-F003's closure, asserted rather than assumed: the 14 template-variant files were
    // de-indented, KNOWN_TEMPLATE_VARIANT_FILES is empty, and no file anywhere renders its
    // body as a code block. If a future prompt reintroduces the shape, this fails.
    assert.equal(stats.indentedBodyCount, 0, "no prompt may render its whole body as a code block");
  });
});

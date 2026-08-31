import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { checkSource, TOUCH_TARGET_FLOOR_PX } from "./check-interaction-primitives.ts";

describe("TABLE_NO_SCROLL_WRAPPER", () => {
  test("a table with no scroll wrapper anywhere in the file is flagged", () => {
    const findings = checkSource(`export function T() { return <table><tbody /></table>; }`, "t.tsx");
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.rule, "TABLE_NO_SCROLL_WRAPPER");
  });

  test("a table inside an overflow-x-auto wrapper is not flagged", () => {
    const findings = checkSource(`<div className="overflow-x-auto"><table /></div>`, "t.tsx");
    assert.deepEqual(findings, []);
  });

  /**
   * The rule is file-level on purpose. The wrapper is frequently several components away from the
   * `<table>` it protects, so requiring them on the same node — which is what an ESLint
   * `no-restricted-syntax` selector could express — would flag correct code constantly. That
   * mismatch is precisely why `ISS-2026-248` could not be built as a lint rule.
   */
  test("the wrapper may be anywhere in the file, not only on the table's own parent", () => {
    const source = `
      function Toolbar() { return <div className="overflow-x-auto" />; }
      function Grid() { return <table />; }
    `;
    assert.deepEqual(checkSource(source, "t.tsx"), []);
  });

  test("overflow-auto and overflow-x-scroll both count", () => {
    assert.deepEqual(checkSource(`<div className="overflow-auto"><table /></div>`, "t.tsx"), []);
    assert.deepEqual(checkSource(`<div className="overflow-x-scroll"><table /></div>`, "t.tsx"), []);
  });
});

describe("UNDERSIZED_TOUCH_TARGET", () => {
  test("a button pinned below the floor is flagged, with the resolved pixel size", () => {
    const findings = checkSource(`<button className="h-8 px-2">Go</button>`, "t.tsx");
    assert.equal(findings.length, 1);
    assert.equal(findings[0]?.rule, "UNDERSIZED_TOUCH_TARGET");
    assert.match(findings[0]?.detail ?? "", /32px/);
  });

  test("exactly at the floor is fine — h-11 is 44px", () => {
    assert.deepEqual(checkSource(`<button className="h-11">Go</button>`, "t.tsx"), []);
    assert.equal(TOUCH_TARGET_FLOOR_PX, 44);
  });

  test("an arbitrary pixel height below the floor is caught too", () => {
    const findings = checkSource(`<button className="min-h-[36px]">Go</button>`, "t.tsx");
    assert.equal(findings.length, 1);
    assert.match(findings[0]?.detail ?? "", /36px/);
  });

  /**
   * The distinction `ISS-2026-248` said a bare AST selector could not make. A 16px icon is
   * decoration; a 16px button is a control nobody can reliably hit.
   */
  test("a small icon is not a touch target — only interactive tags are inspected", () => {
    assert.deepEqual(checkSource(`<button className="h-11"><svg className="h-4 w-4" /></button>`, "t.tsx"), []);
    assert.deepEqual(checkSource(`<div className="h-4 w-4" />`, "t.tsx"), []);
  });

  test("a height that is not a fixed pixel size is left alone", () => {
    assert.deepEqual(checkSource(`<button className="h-full">Go</button>`, "t.tsx"), []);
    assert.deepEqual(checkSource(`<button className="h-auto">Go</button>`, "t.tsx"), []);
  });
});

describe("label association exempts a small checkbox", () => {
  test("explicit association: a <label htmlFor> naming the control's id", () => {
    const source = `<input id="agree" type="checkbox" className="h-4 w-4" /><label htmlFor="agree">Agree</label>`;
    assert.deepEqual(checkSource(source, "t.tsx"), []);
  });

  /**
   * The form that broke the first draft of this checker. Two perfectly correct controls in
   * `admin/scheduler/scheduler-admin-panel.tsx` were flagged because the rule knew only
   * `htmlFor`. A guard that recognises one of HTML's two label-association forms does not find
   * defects — it finds the other form.
   */
  test("implicit association: the control simply sits inside its <label>", () => {
    const source = `<label className="flex"><input type="checkbox" className="h-4 w-4" /> Enabled</label>`;
    assert.deepEqual(checkSource(source, "t.tsx"), []);
  });

  test("a closed label before the control does not exempt it", () => {
    const source = `<label>Something</label><input type="checkbox" className="h-4 w-4" />`;
    assert.equal(checkSource(source, "t.tsx").length, 1);
  });

  test("an id nobody points at is not an association", () => {
    const source = `<input id="orphan" type="checkbox" className="h-4 w-4" />`;
    assert.equal(checkSource(source, "t.tsx").length, 1);
  });

  /** The exemption is for checkboxes and radios, not a general escape hatch for small buttons. */
  test("a small button inside a label is still flagged — a label does not operate a button", () => {
    assert.equal(checkSource(`<label><button className="h-8">Go</button></label>`, "t.tsx").length, 1);
  });
});

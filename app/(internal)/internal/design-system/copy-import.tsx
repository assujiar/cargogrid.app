"use client";

import { useState } from "react";

/** Copyable import snippet + source file reference, shown on every IMPLEMENTED component card. Falls back to a visible select-all hint if the Clipboard API is unavailable (e.g. non-secure context) rather than failing silently. */
export function CopyImport({ importSnippet, sourceFile }: { readonly importSnippet: string; readonly sourceFile: string }) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(importSnippet);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="flex flex-col gap-1 rounded-md border border-[var(--ds-border)] bg-[var(--ds-bg)] p-2 text-xs">
      <div className="flex items-center justify-between gap-2">
        <code className="overflow-x-auto whitespace-nowrap font-mono">{importSnippet}</code>
        <button
          type="button"
          onClick={handleCopy}
          className="flex-shrink-0 rounded border border-[var(--ds-border)] px-2 py-0.5 text-[var(--ds-text)]"
        >
          {copied ? "Copied" : "Copy"}
        </button>
      </div>
      <span className="text-[var(--ds-text-secondary)]">Source: {sourceFile}</span>
    </div>
  );
}

/** Button group primitive (`docs/design-system/02_COMPONENTS.md` "Button group") -- a segmented set of mutually exclusive or related actions. Server-safe, purely layout: joins adjacent `Button`s into one visual control via `role="group"` and shared border-radius trimming. */

import type { ReactNode } from "react";

export function ButtonGroup({ children, label }: { readonly children: ReactNode; readonly label: string }) {
  return (
    <div role="group" aria-label={label} className="inline-flex [&>button]:rounded-none [&>button:first-child]:rounded-l-md [&>button:last-child]:rounded-r-md [&>button:not(:first-child)]:-ml-px">
      {children}
    </div>
  );
}

/** Link primitive (`docs/design-system/02_COMPONENTS.md` "Link") -- inline/styled navigation, distinct from Button's `asChild` composition (which makes a link *look like* a button; this makes a link look like a link). Server-safe, wraps `next/link`. */

import NextLink from "next/link";
import type { ComponentProps } from "react";

export function Link({ className, ...rest }: ComponentProps<typeof NextLink>) {
  return <NextLink className={`text-primary underline underline-offset-2 hover:text-primary-hover ${className ?? ""}`} {...rest} />;
}

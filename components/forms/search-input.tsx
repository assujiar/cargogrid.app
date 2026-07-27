/**
 * Search input primitive (`docs/design-system/02_COMPONENTS.md` "Search input").
 * Renders `type="search"` with `role="searchbox"`; deliberately does NOT implement
 * debouncing or client-side filtering itself -- `09_UX_DESIGN_SYSTEM_WORKSTREAM.md`
 * §11's binding rule is server-side FTS/trigram search, never a client-side filter of a
 * large dataset. A future search-driven screen wires this to a debounced
 * `router.push`/server action; this primitive only owns the field's appearance.
 */

import { forwardRef } from "react";
import { Input, type InputProps } from "./input.tsx";

export type SearchInputProps = Omit<InputProps, "type">;

export const SearchInput = forwardRef<HTMLInputElement, SearchInputProps>(function SearchInput(props, ref) {
  return <Input ref={ref} type="search" role="searchbox" {...props} />;
});

/**
 * Form section primitive (`docs/design-system/02_COMPONENTS.md` "Form section") --
 * grouped fields with a heading, at a readable max-width for long forms (`03_LAYOUT_
 * NAVIGATION.md` §1's disclosed "no `--content-max-width` token yet" gap: uses a fixed
 * `max-w-2xl` utility directly rather than inventing a token this checkpoint has no
 * authority to decide).
 */

import type { ReactNode } from "react";

export interface FormSectionProps {
  readonly title: ReactNode;
  readonly description?: ReactNode;
  readonly children: ReactNode;
}

export function FormSection({ title, description, children }: FormSectionProps) {
  return (
    <section className="flex max-w-2xl flex-col gap-4">
      <div>
        <h2 className="text-base font-semibold text-text-primary">{title}</h2>
        {description ? <p className="mt-0.5 text-sm text-text-secondary">{description}</p> : null}
      </div>
      <div className="flex flex-col gap-4">{children}</div>
    </section>
  );
}

/**
 * Tailwind v4's CSS-first `@theme` configuration needs no `tailwind.config.js` --
 * `@tailwindcss/postcss` is the only PostCSS plugin required (ADR-0006,
 * docs/standards/DESIGN_SYSTEM.md §1).
 */
const config = {
  plugins: {
    "@tailwindcss/postcss": {},
  },
};

export default config;

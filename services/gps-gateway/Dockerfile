# CargoGrid GPS Gateway (ATW-226D) -- an always-on raw TCP Teltonika Codec 8 Extended
# listener, independently deployed from the CargoGrid Next.js app (see README.md for
# why: 220_*.md §6 requires a static public endpoint and configurable raw TCP ports,
# explicitly not a Vercel Function or an ordinary Supabase Edge Function).
#
# Two-stage build: the builder stage installs devDependencies (typescript, for the
# typecheck gate only -- this package ships as plain .ts run via
# node --experimental-strip-types, never a compiled dist/, so there is nothing to
# actually emit); the runtime stage installs production dependencies only.

FROM node:22-slim AS builder
WORKDIR /app
COPY package.json pnpm-lock.yaml* ./
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
RUN pnpm install --frozen-lockfile || pnpm install
COPY tsconfig.json ./
COPY src ./src
COPY test ./test
RUN pnpm run typecheck

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package.json ./
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
RUN pnpm install --prod --frozen-lockfile || pnpm install --prod
COPY src ./src

# Raw TCP listener (device connections) and the health/readiness/metrics HTTP server --
# both configurable via GPS_GATEWAY_TCP_PORT/GPS_GATEWAY_HEALTH_PORT env vars; these
# EXPOSE defaults document the image's own out-of-the-box ports.
EXPOSE 6060 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:' + (process.env.GPS_GATEWAY_HEALTH_PORT || 8080) + '/healthz').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "--experimental-strip-types", "src/index.ts"]

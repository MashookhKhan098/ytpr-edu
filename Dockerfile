# syntax=docker/dockerfile:1.7

# =============================
# Base builder image
# =============================
FROM node:18-alpine AS deps
WORKDIR /app

# Install system deps if needed (e.g., sharp). Keep minimal for Alpine.
RUN apk add --no-cache libc6-compat

# Install dependencies based on lockfile
COPY package.json pnpm-lock.yaml* package-lock.json* yarn.lock* ./

# Prefer pnpm if available, fall back to npm
RUN if [ -f pnpm-lock.yaml ]; then \
      corepack enable && corepack prepare pnpm@latest --activate && pnpm i --frozen-lockfile; \
    elif [ -f yarn.lock ]; then \
      corepack enable && corepack prepare yarn@stable --activate && yarn install --frozen-lockfile; \
    else \
      npm ci; \
    fi

# =============================
# Builder - compile Next.js
# =============================
FROM node:18-alpine AS builder
WORKDIR /app
ENV NODE_ENV=production

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Build Next.js app
RUN if [ -f pnpm-lock.yaml ]; then \
      corepack enable && corepack prepare pnpm@latest --activate && pnpm run build; \
    elif [ -f yarn.lock ]; then \
      corepack enable && corepack prepare yarn@stable --activate && yarn build; \
    else \
      npm run build; \
    fi

# =============================
# Runner - minimal runtime
# =============================
FROM node:18-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
ENV NEXT_TELEMETRY_DISABLED=1

# Create non-root user
RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001

# Copy only necessary files for production runtime
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/next.config.mjs ./next.config.mjs
COPY --from=builder /app/public ./public

# Standalone output (Next 13+)
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# Ensure correct ownership
RUN chown -R nextjs:nodejs /app
USER nextjs

EXPOSE 3000

# Healthcheck optional; can also be set in compose
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/ || exit 1

CMD ["node", "server.js"]



FROM node:20-alpine AS builder

WORKDIR /app
COPY package*.json ./
# Install ALL dependencies (including TypeScript devDependencies) for the build step
RUN npm ci

COPY tsconfig.json ./
COPY src/ ./src/
RUN npm run build

# ── Production dependencies (separate stage to keep runtime image small) ──
FROM node:20-alpine AS prod-deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# ── Runtime image ──────────────────────────────────────────────────
FROM node:20-alpine

WORKDIR /app

# Run as non-root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=prod-deps --chown=appuser:appgroup /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:appgroup /app/dist ./dist

USER appuser

EXPOSE 8090
CMD ["node", "dist/src/index.js"]

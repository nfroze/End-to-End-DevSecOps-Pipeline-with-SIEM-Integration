FROM node:22-alpine AS builder

# Build stage - install dependencies
WORKDIR /app
COPY app/package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM node:22-alpine

# Upgrade all Alpine packages to pick up latest security patches
RUN apk upgrade --no-cache

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Remove package managers - not needed at runtime, eliminates npm/yarn/corepack CVEs
RUN rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /opt/yarn-v*

# Create non-root user with specific UID/GID matching K8s security context
RUN addgroup -g 10001 -S nodejs && \
    adduser -u 10001 -S nodejs -G nodejs

# Create app directory with correct permissions
WORKDIR /app

# Copy node_modules from builder
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy application files
COPY --chown=nodejs:nodejs app/package*.json ./
COPY --chown=nodejs:nodejs app/index.js ./
COPY --chown=nodejs:nodejs app/routes ./routes
COPY --chown=nodejs:nodejs app/public ./public

# Create temp directory for Node.js
RUN mkdir -p /tmp/app && chown -R nodejs:nodejs /tmp/app

# Switch to non-root user
USER nodejs

# Expose port
EXPOSE 3000

# Set Node.js temp directory
ENV NODE_ENV=production
ENV NODE_TMPDIR=/tmp/app

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (res) => {res.on('data', () => {}); res.on('end', () => {process.exit(res.statusCode === 200 ? 0 : 1)})}).on('error', () => {process.exit(1)})"

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "index.js"]

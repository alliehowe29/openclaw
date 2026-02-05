FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Set up pnpm global bin directory for node user
ENV PNPM_HOME="/home/node/.local/share/pnpm"
ENV PATH="${PNPM_HOME}:${PATH}"
RUN mkdir -p /home/node/.local/share/pnpm && \
    chown -R node:node /home/node/.local

# Pre-install mcporter globally for the node user
RUN pnpm add -g mcporter

# Create config directory for ECS deployment
# trustedProxies includes VPC CIDR to trust ALB proxy headers
# controlUi.dangerouslyDisableDeviceAuth skips device pairing for Control UI (replace with Tailscale later)
RUN mkdir -p /home/node/.openclaw && \
    echo '{"gateway":{"mode":"local","trustedProxies":["10.2.0.0/16"],"controlUi":{"dangerouslyDisableDeviceAuth":true}},"browser":{"enabled":true,"defaultProfile":"browserbase","profiles":{"browserbase":{"cdpUrl":"wss://connect.browserbase.com?apiKey=${BROWSERBASE_API_KEY}&projectId=${BROWSERBASE_PROJECT_ID}","color":"#00AA00"}}}}' > /home/node/.openclaw/openclaw.json && \
    chown -R node:node /home/node/.openclaw

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node

CMD ["node", "dist/index.js"]

FROM node:20-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    jq \
    python3 \
    python3-pip \
    bash \
    bc \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | \
    dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
    tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Install openclaw — each step must succeed independently
ARG CACHEBUST=1
RUN npm cache clean --force && npm install -g openclaw
RUN set -ex; \
    PKG_DIR="$(npm root -g)/openclaw"; \
    echo "--- top-level files ---"; \
    ls "$PKG_DIR/"; \
    echo "--- bin + main ---"; \
    node -p "JSON.stringify(require('$PKG_DIR/package.json').bin)"; \
    node -p "require('$PKG_DIR/package.json').main"
RUN set -ex; \
    PKG_DIR="$(npm root -g)/openclaw"; \
    if [ -f "$PKG_DIR/openclaw.mjs" ]; then \
      ENTRY="openclaw.mjs"; \
    else \
      ENTRY=$(node -p "require('$PKG_DIR/package.json').main || 'dist/index.js'"); \
    fi; \
    echo "entry=$ENTRY"; \
    printf '#!/bin/sh\nexec node "%s/%s" "$@"\n' "$PKG_DIR" "$ENTRY" > /usr/local/bin/openclaw; \
    chmod +x /usr/local/bin/openclaw; \
    openclaw --version

WORKDIR /app
COPY . .
RUN npm install

# Use linux-specific start script
CMD ["bash", "scripts/start-linux.sh"]

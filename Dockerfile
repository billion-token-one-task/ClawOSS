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

# Install openclaw and ensure binary is in PATH
RUN npm install -g openclaw \
 && ls "$(npm root -g)/openclaw/openclaw.mjs" 2>/dev/null \
    || { echo "openclaw.mjs not at expected path, searching..."; find "$(npm root -g)" -name "openclaw.mjs" 2>/dev/null; } \
 && if ! which openclaw >/dev/null 2>&1; then \
      echo "npm did not create bin link, creating wrapper..." \
      && printf '#!/bin/sh\nexec node "%s/openclaw/openclaw.mjs" "$@"\n' "$(npm root -g)" > /usr/local/bin/openclaw \
      && chmod +x /usr/local/bin/openclaw; \
    fi \
 && openclaw --version

WORKDIR /app
COPY . .
RUN npm install

# Use linux-specific start script
CMD ["bash", "scripts/start-linux.sh"]

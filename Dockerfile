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

# Install openclaw — diagnose actual package layout then link binary
RUN npm install -g openclaw \
 && echo "=== installed files (top-level) ===" \
 && ls "$(npm root -g)/openclaw/" \
 && echo "=== package.json bin + main ===" \
 && node -e "var p=require('$(npm root -g)/openclaw/package.json'); console.log('bin:',JSON.stringify(p.bin)); console.log('main:',p.main);" \
 && echo "=== all .mjs and cli files ===" \
 && find "$(npm root -g)/openclaw" -maxdepth 2 \( -name "*.mjs" -o -name "cli*" \) 2>/dev/null | head -20 \
 && echo "=== /usr/local/bin/openclaw* ===" \
 && ls -la /usr/local/bin/openclaw* 2>/dev/null || echo "(none)"

WORKDIR /app
COPY . .
RUN npm install

# Use linux-specific start script
CMD ["bash", "scripts/start-linux.sh"]

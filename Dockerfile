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

# Install openclaw
RUN npm install -g openclaw \
 && npm root -g \
 && npm bin -g \
 && ls -la $(npm root -g) \
 && ls -la $(npm root -g)/openclaw \
 && ls -la /usr/local/bin || true \
 && find / -name "openclaw*" 2>/dev/null | head -50

RUN which openclaw && echo "openclaw found" || echo "openclaw not found"
RUN openclaw --version

WORKDIR /app
COPY . .
RUN npm install

# Use linux-specific start script
CMD ["bash", "scripts/start-linux.sh"]

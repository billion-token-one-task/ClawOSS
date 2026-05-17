# ClawOSS agent — Linux container image.
#
# This image runs the OpenClaw gateway + the clawoss agent configuration
# in a single container. It's the Linux-native counterpart to
# scripts/restart.sh's launchd flow on macOS.
#
# Build:
#   docker build -f deploy/docker/Dockerfile -t clawoss-agent .
#
# Run (see deploy/docker/docker-compose.yml for the real invocation):
#   docker run --env-file .env -v clawoss_state:/home/clawoss/.openclaw clawoss-agent

FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# System deps used by scripts + subagents: git, gh CLI, jq, python3, curl, ca-certs.
# The git repos worked on by the agent get cloned inside /tmp at runtime, so
# git itself must be present. gh is used for every PR operation.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl git gnupg jq python3 python3-pip tini \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Install openclaw CLI globally. Pinned to a known-good range; operators can
# override with --build-arg OPENCLAW_VERSION=x.y.z.
ARG OPENCLAW_VERSION=latest
RUN npm install -g "openclaw@${OPENCLAW_VERSION}" \
 && openclaw --version

# Non-root user so the agent doesn't run as root inside the container.
RUN useradd --create-home --shell /bin/bash --uid 1000 clawoss
WORKDIR /app
COPY --chown=clawoss:clawoss . /app

# Install project deps (workspaces include the dashboard — skip the heavy
# dashboard install here; run the agent and the dashboard in separate images
# if both are needed).
RUN npm install --omit=dev --ignore-scripts --workspaces=false \
 && chown -R clawoss:clawoss /app

USER clawoss
ENV HOME=/home/clawoss
ENV PATH=/home/clawoss/.local/bin:/usr/local/lib/node_modules/.bin:$PATH

# Entrypoint handles env validation, config deploy, gateway start, and then
# execs openclaw gateway run as PID 1 (via tini).
COPY --chown=clawoss:clawoss deploy/docker/entrypoint.sh /usr/local/bin/clawoss-entrypoint
RUN chmod +x /usr/local/bin/clawoss-entrypoint

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/clawoss-entrypoint"]
CMD []

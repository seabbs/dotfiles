# Shared base for all pi-sandbox-dev profiles.
# Replaces thegreataxios/pi-sandbox:latest (arm64-only) with a multi-arch
# Debian base that has the core agent toolset installed.
FROM debian:bookworm-slim

USER root

# Core agent toolset (mirrors thegreataxios/pi-sandbox contents)
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates git curl wget jq ripgrep fd-find bat \
      python3 python3-pip python3-venv \
      nodejs npm \
      build-essential pkg-config \
      openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# Create the pi user (uid 1000) that pi-container-sandbox runs as
RUN groupadd -g 1000 pi && useradd -u 1000 -g 1000 -m -s /bin/bash pi

# Install go-task (Taskfile CLI)
RUN curl -fsSL "https://github.com/go-task/task/releases/latest/download/task_linux_amd64.tar.gz" \
    | tar -xzf - -C /usr/local/bin task

# Default working directory
WORKDIR /workspace

USER 1000:1000

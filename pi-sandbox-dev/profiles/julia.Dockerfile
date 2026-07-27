FROM debian:bookworm-slim

USER root

# Core agent toolset
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

# Install Julia system-wide from official binary tarball.
# Update JULIA_VERSION / JULIA_MAJOR when new releases come out.
ARG JULIA_VERSION=1.11.5
ARG JULIA_MAJOR=1.11
RUN curl -fsSL "https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MAJOR}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" \
    | tar -xzf - -C /opt/ \
    && ln -sf "/opt/julia-${JULIA_VERSION}/bin/julia" /usr/local/bin/julia

# Shared Julia depot writable by the runtime user (uid 1000)
ENV JULIA_DEPOT_PATH=/opt/julia-depot
RUN mkdir -p /opt/julia-depot && chown 1000:1000 /opt/julia-depot

WORKDIR /workspace

USER 1000:1000

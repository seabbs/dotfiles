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

# R + system dependencies for common R packages
RUN apt-get update && apt-get install -y --no-install-recommends \
      r-base r-base-dev \
      libxml2-dev libcurl4-openssl-dev libssl-dev \
      libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
      libfreetype6-dev libpng-dev libtiff-dev libjpeg-dev \
      pandoc \
    && rm -rf /var/lib/apt/lists/*

# Create the pi user (uid 1000) that pi-container-sandbox runs as
RUN groupadd -g 1000 pi && useradd -u 1000 -g 1000 -m -s /bin/bash pi

# Install go-task (Taskfile CLI)
RUN curl -fsSL "https://github.com/go-task/task/releases/latest/download/task_linux_amd64.tar.gz" \
    | tar -xzf - -C /usr/local/bin task

# Install common R packages system-wide
RUN R -e 'install.packages(c("devtools","usethis","testthat","pkgdown","rcmdcheck"), repos="https://cloud.r-project.org")'

WORKDIR /workspace

USER 1000:1000

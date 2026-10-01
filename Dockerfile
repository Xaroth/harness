# syntax=docker/dockerfile:1
# Each install step is a script under docker/install/, bind-mounted so a change
# to one script only rebuilds that layer. Pins below are bumped by CI.
FROM debian:trixie-slim

ARG NODE_VERSION=24.21.0
ARG T3_VERSION=0.0.44
ARG CLAUDE_CODE_VERSION=2.1.286
ARG PLAYWRIGHT_MCP_VERSION=0.0.83
ARG CHROME_DEVTOOLS_MCP_VERSION=1.10.1
ARG GO_VERSION=1.27.1
ARG RUST_VERSION=1.98.1
ARG CLOUDFLARED_VERSION=2026.9.3
ARG JJ_VERSION=0.45.1
ARG FNM_VERSION=1.39.0
ARG UV_VERSION=0.12.21
ARG GH_MIN_VERSION=2.81.0

ENV DEBIAN_FRONTEND=noninteractive

RUN --mount=type=bind,source=docker/install/apt.sh,target=/tmp/i.sh \
    --mount=type=bind,source=docker/apt-packages.txt,target=/tmp/apt-packages.txt \
    /tmp/i.sh
RUN --mount=type=bind,source=docker/install/gh.sh,target=/tmp/i.sh /tmp/i.sh
RUN --mount=type=bind,source=docker/install/node.sh,target=/tmp/i.sh /tmp/i.sh
RUN --mount=type=bind,source=docker/install/cloudflared.sh,target=/tmp/i.sh /tmp/i.sh
RUN --mount=type=bind,source=docker/install/go.sh,target=/tmp/i.sh /tmp/i.sh
RUN --mount=type=bind,source=docker/install/rust.sh,target=/tmp/i.sh /tmp/i.sh
RUN --mount=type=bind,source=docker/install/uv.sh,target=/tmp/i.sh /tmp/i.sh
RUN --mount=type=bind,source=docker/install/jj.sh,target=/tmp/i.sh /tmp/i.sh
RUN --mount=type=bind,source=docker/install/fnm.sh,target=/tmp/i.sh /tmp/i.sh
RUN --mount=type=bind,source=docker/install/npm-globals.sh,target=/tmp/i.sh /tmp/i.sh
RUN --mount=type=bind,source=docker/install/user.sh,target=/tmp/i.sh /tmp/i.sh

COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 docker/bin/ /usr/local/bin/
COPY --chown=code:code docker/bashrc /home/code/.bashrc
COPY --chown=code:code docker/bash_profile /home/code/.bash_profile
# /etc/profile resets PATH in login shells, and t3 reads PATH from `bash -ilc`
COPY docker/profile.sh /etc/profile.d/harness.sh
COPY docker/sshd_config /etc/ssh/sshd_harness.conf

# config, all on the /config volume
ENV CLAUDE_CONFIG_DIR=/config/claude \
    T3CODE_HOME=/config/t3 \
    GH_CONFIG_DIR=/config/gh \
    GIT_CONFIG_GLOBAL=/config/git/config \
    JJ_CONFIG=/config/jj/config.toml \
    HISTFILE=/config/shell/bash_history

# caches, all on the /cache volume
ENV GOPATH=/cache/go \
    GOMODCACHE=/cache/go/pkg/mod \
    GOCACHE=/cache/go/build \
    CARGO_HOME=/cache/cargo \
    UV_CACHE_DIR=/cache/uv \
    UV_PYTHON_INSTALL_DIR=/cache/uv/python \
    NPM_CONFIG_CACHE=/cache/npm \
    FNM_DIR=/cache/fnm \
    AUTO_UPDATE_PREFIX=/cache/npm-global

# tool settings
ENV NODE_VERSION=${NODE_VERSION} \
    WORKSPACE=/workspace \
    SHELL=/bin/bash \
    DISABLE_AUTOUPDATER=1 \
    RUSTUP_HOME=/opt/rustup \
    NPM_CONFIG_PREFIX=/opt/npm-global \
    CHROME_PATH=/usr/bin/chromium \
    PUPPETEER_SKIP_DOWNLOAD=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    T3CODE_HOST=0.0.0.0 \
    T3CODE_PORT=3773 \
    T3CODE_CLOUDFLARED_PATH=/usr/local/bin/cloudflared \
    PATH=/cache/npm-global/bin:/opt/npm-global/bin:/opt/node/current/bin:/usr/local/go/bin:/opt/cargo/bin:/cache/go/bin:$PATH

VOLUME ["/config", "/cache"]
EXPOSE 3773

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS -o /dev/null http://127.0.0.1:3773/.well-known/t3/environment || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["serve"]

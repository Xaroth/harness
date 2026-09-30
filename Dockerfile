# syntax=docker/dockerfile:1
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

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git git-lfs openssh-client build-essential \
      python3 python3-dev python3-venv clang lld cmake pkg-config gdb tini gosu \
      jq ripgrep fd-find sqlite3 unzip xz-utils less nano procps file tzdata \
      qrencode iproute2 ffmpeg imagemagick postgresql-client redis-tools \
      chromium fonts-liberation fonts-dejavu-core fonts-noto-core \
      fonts-noto-color-emoji \
 && ln -s /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

# Trixie's gh is too old for t3
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/* \
 && v="$(gh --version | awk 'NR==1{print $3}')" \
 && dpkg --compare-versions "$v" ge "$GH_MIN_VERSION" \
 || { echo "gh $v < $GH_MIN_VERSION" >&2; exit 1; }

# fnm layout, so the entrypoint can link it in and `fnm current` reports the version
RUN mkdir -p "/opt/node/v${NODE_VERSION}/installation" \
 && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    | tar -xJ -C "/opt/node/v${NODE_VERSION}/installation" --strip-components=1 --no-same-owner \
 && ln -s "v${NODE_VERSION}/installation" /opt/node/current \
 && PATH="/opt/node/current/bin:$PATH" corepack enable \
 && /opt/node/current/bin/node --version

RUN curl -fsSL -o /usr/local/bin/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64" \
 && chmod 0755 /usr/local/bin/cloudflared \
 && cloudflared --version

RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -xz -C /usr/local \
 && /usr/local/go/bin/go version

# Owned by code so rustup/cargo install work at runtime; registry goes to /cache/cargo
RUN export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo \
 && curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path \
      --profile minimal --default-toolchain "$RUST_VERSION" -c clippy -c rustfmt \
 && rm -rf /opt/cargo/registry /opt/cargo/git /opt/rustup/downloads /opt/rustup/tmp \
 && chown -R 1000:1000 /opt/rustup /opt/cargo \
 && /opt/cargo/bin/rustc --version && /opt/cargo/bin/cargo --version

RUN curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" \
    | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh \
 && uv --version

RUN tmp="$(mktemp -d)" \
 && curl -fsSL "https://github.com/jj-vcs/jj/releases/download/v${JJ_VERSION}/jj-v${JJ_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    | tar -xz -C "$tmp" \
 && install -m 0755 "$tmp/jj" /usr/local/bin/jj \
 && rm -rf "$tmp" \
 && jj --version

RUN tmp="$(mktemp -d)" \
 && curl -fsSL -o "$tmp/fnm.zip" "https://github.com/Schniz/fnm/releases/download/v${FNM_VERSION}/fnm-linux.zip" \
 && unzip -q "$tmp/fnm.zip" -d "$tmp" \
 && install -m 0755 "$tmp/fnm" /usr/local/bin/fnm \
 && rm -rf "$tmp" \
 && fnm --version

# Not --ignore-scripts: claude-code's postinstall copies its native binary in
RUN export PATH="/opt/npm-global/bin:/opt/node/current/bin:$PATH" \
      NPM_CONFIG_PREFIX=/opt/npm-global NPM_CONFIG_CACHE=/tmp/npm-cache \
      PUPPETEER_SKIP_DOWNLOAD=1 PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
      CLAUDE_CONFIG_DIR=/tmp/claude-build DISABLE_AUTOUPDATER=1 \
 && npm install -g --no-fund --no-audit \
      "t3@${T3_VERSION}" \
      "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
      "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
      "chrome-devtools-mcp@${CHROME_DEVTOOLS_MCP_VERSION}" \
 && find /opt/npm-global -name '*.map' -type f -delete \
 && find /opt/npm-global -type d -path '*/prebuilds/*' ! -path '*/prebuilds/linux-x64*' -prune -exec rm -rf {} + \
 && t3 --version \
 && claude --version \
 && playwright-mcp --version \
 && chrome-devtools-mcp --version \
 && npm cache clean --force \
 && rm -rf /tmp/npm-cache /tmp/claude-build /root/.npm /root/.t3 /root/.cache /root/.claude* \
 && chown -R 1000:1000 /opt/npm-global

RUN groupadd --gid 1000 code \
 && useradd --uid 1000 --gid 1000 --create-home --home-dir /home/code --shell /bin/bash code \
 && mkdir -p /workspace && chown 1000:1000 /workspace

# /etc/profile resets PATH in login shells, and t3 reads PATH from `bash -ilc`
COPY docker/profile.sh /etc/profile.d/harness.sh

COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 docker/bin/ /usr/local/bin/
COPY --chown=code:code docker/bashrc /home/code/.bashrc
COPY --chown=code:code docker/bash_profile /home/code/.bash_profile

ENV NODE_VERSION=${NODE_VERSION} \
    WORKSPACE=/workspace \
    CLAUDE_CONFIG_DIR=/config/claude \
    T3CODE_HOME=/config/t3 \
    GH_CONFIG_DIR=/config/gh \
    GIT_CONFIG_GLOBAL=/config/git/config \
    JJ_CONFIG=/config/jj/config.toml \
    HISTFILE=/config/shell/bash_history \
    GOPATH=/cache/go \
    GOMODCACHE=/cache/go/pkg/mod \
    GOCACHE=/cache/go/build \
    CARGO_HOME=/cache/cargo \
    RUSTUP_HOME=/opt/rustup \
    UV_CACHE_DIR=/cache/uv \
    UV_PYTHON_INSTALL_DIR=/cache/uv/python \
    NPM_CONFIG_CACHE=/cache/npm \
    NPM_CONFIG_PREFIX=/opt/npm-global \
    FNM_DIR=/cache/fnm \
    SHELL=/bin/bash \
    DISABLE_AUTOUPDATER=1 \
    CHROME_PATH=/usr/bin/chromium \
    PUPPETEER_SKIP_DOWNLOAD=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    T3CODE_HOST=0.0.0.0 \
    T3CODE_PORT=3773 \
    T3CODE_CLOUDFLARED_PATH=/usr/local/bin/cloudflared \
    PATH=/opt/npm-global/bin:/opt/node/current/bin:/usr/local/go/bin:/opt/cargo/bin:/cache/go/bin:$PATH

VOLUME ["/config", "/cache"]
EXPOSE 3773

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS -o /dev/null http://127.0.0.1:3773/.well-known/t3/environment || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["serve"]

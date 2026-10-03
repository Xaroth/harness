# harness: design notes

Claude Code driven by T3 Code, in one Docker image. Fresh build, nothing
from the old draft survives.

## Decisions (agreed 2026-09-30)

| Topic | Choice |
| --- | --- |
| Base | `debian:trixie-slim` + official Node tarball in `/opt/node` (pinned ARG), amd64 only, one image |
| Agents | Claude Code only |
| User | `code`, home `/home/code`, runtime `PUID`/`PGID` (root entrypoint, gosu step-down) |
| Config | named volume at `/config`, every tool pointed there by env var or symlink |
| Cache | named volume at `/cache` (Go mod, cargo, uv, npm, fnm). Drop the compose line = ephemeral |
| Workspace | `WORKSPACE` env, default `/workspace`, mounted at the same path inside |
| Network | `127.0.0.1:3773` only. User's reverse proxy does TLS |
| Browser | Chromium + playwright-mcp + chrome-devtools-mcp, registered into claude user scope on first boot |
| Python | debian python3 + uv, nothing else |
| Node | image Node in `/opt/node`, also registered into fnm via symlink at boot; fnm in `/cache/fnm` holds extra project versions |
| sudo | none |
| Projects | manual, no auto-add |
| Auth | interactive `claude` login, creds on `/config/claude` |
| VCS | jj colocated, author `Xaroth Brook <xaroth+github@xaroth.nl>`, MIT, no remote yet |
| Registry | `ghcr.io/xaroth/harness`, `:latest` on main, `:vX.Y.Z` on tag |
| Updates | weekly night cron + manual, one bump PR, merge auto-tags a patch |
| Auto-update | opt-in `AUTO_UPDATE=claude,t3[@spec]`: `update-tools` at boot npm-installs newer versions into `/cache/npm-global`, ahead of `/opt/npm-global` on PATH; falls back to the image copy on any failure (agreed 2026-10-01) |
| sshd | opt-in `SSHD=1`, key auth, user code, host key on /config; for t3's open-in-editor VS Code Remote SSH link (`<hostname>.local`) |
| Keyring | opt-in `KEYRING=1`, session D-Bus at `/run/user/<uid>/bus` plus unlocked gnome-keyring, empty password, throwaway |
| Telemetry | off by default (`T3_TELEMETRY=0`), PostHog and OTel both disabled |
| CI check | boot, health endpoint, `--version` for each tool, MCP handshake, volume perms |

## Repo layout

```
harness/
  Dockerfile                   one RUN per docker/install/*.sh, bind-mounted
  compose.yaml
  .env.example
  .dockerignore
  .gitignore
  LICENSE                      MIT
  README.md
  docs/design.md               these notes
  docker/
    apt-packages.txt           one package per line, grouped with comments
    install/                   one script per tool, run at build
    entrypoint.sh
    bin/
      pair                     t3 auth pairing create --base-url ... + QR
      doctor                   what's installed, signed in, healthy
      register-mcp             claude mcp add for both browser servers (idempotent)
      update-tools             AUTO_UPDATE overlay for claude/t3 in /cache/npm-global
  scripts/
    smoke-test.sh              runs smoke.d/NN-*.sh in order against a booted container
    smoke.d/                   one file per check group, _lib.sh shared helpers
    bump-versions.sh           runs bump.d/<ARG>.sh per pin, rewrites Dockerfile
    bump.d/                    <name>.sh per ARG <NAME>_VERSION, _lib.sh shared helpers
  .github/
    workflows/
      build.yml                PR + main + tag + workflow_call: build, smoke, push, tag release on bump merge
      bump.yml                 cron + manual: bump-versions.sh, open PR, verify via build.yml, comment
```

## Dockerfile

Single stage, ordered slow-changing to fast-changing so bumps reuse layers.

Pins (build args, current as of 2026-09-30):

```
NODE_VERSION=24.21.0
T3_VERSION=0.0.44
CLAUDE_CODE_VERSION=2.1.286
PLAYWRIGHT_MCP_VERSION=0.0.83
CHROME_DEVTOOLS_MCP_VERSION=1.10.1
GO_VERSION=1.27.1
RUST_VERSION=1.98.1
CLOUDFLARED_VERSION=2026.9.3
JJ_VERSION=0.45.1
FNM_VERSION=1.39.0
UV_VERSION=0.12.21
GH_MIN_VERSION=2.81.0        # gh itself unpinned, from GitHub apt repo, asserted >= this
```

Steps:

1. apt: ca-certificates curl gnupg git git-lfs openssh-client build-essential
   python3 python3-dev python3-venv clang lld cmake pkg-config gdb tini gosu
   jq ripgrep fd-find sqlite3 unzip xz-utils less nano procps file tzdata
   qrencode iproute2 ffmpeg imagemagick postgresql-client redis-tools
   chromium fonts-liberation fonts-dejavu-core fonts-noto-core
   fonts-noto-color-emoji. `--no-install-recommends`, clean lists.
   fonts-noto-cjk skipped (~100 MB), add later if needed.
2. gh from GitHub apt repo, assert version >= 2.81.
3. Node tarball to `/opt/node/v$NODE_VERSION/installation`, `/opt/node/current` symlink. Enable corepack. `/opt/node/current/bin` on PATH.
4. cloudflared binary to `/usr/local/bin`, `T3CODE_CLOUDFLARED_PATH` set so t3 never downloads its own.
5. Go tarball to `/usr/local/go`.
6. rustup with `RUSTUP_HOME=/opt/rustup`, `CARGO_HOME=/opt/cargo`, profile minimal + clippy + rustfmt.
   At runtime `CARGO_HOME=/cache/cargo` for registry/git; PATH keeps `/opt/cargo/bin`.
7. uv to `/usr/local/bin`. `UV_CACHE_DIR=/cache/uv`, `UV_PYTHON_INSTALL_DIR=/cache/uv/python`.
8. jj musl tarball to `/usr/local/bin`.
9. fnm binary to `/usr/local/bin`. `FNM_DIR=/cache/fnm`. Nothing installed at build time;
   the entrypoint links the image Node in (see below). Verified: fnm accepts a symlinked
   `node-versions/vX.Y.Z/installation` as a real version, `fnm default`/`fnm use` work on it.
10. npm globals to `/opt/npm-global` (owned by `code`): t3, claude-code, both MCP servers.
   Strip `*.map` and non-linux prebuilt dirs. `npm cache clean`.
   Not `--ignore-scripts`: claude-code's postinstall copies the native binary in.
11. Create `code` uid/gid 1000.
12. `COPY docker/` scripts, chmod.
13. ENV block, VOLUME, EXPOSE 3773, HEALTHCHECK on `/.well-known/t3/environment`,
    `ENTRYPOINT ["tini","--","/usr/local/bin/entrypoint.sh"]`, `CMD ["serve"]`.

Env (image):

```
CLAUDE_CONFIG_DIR=/config/claude
T3CODE_HOME=/config/t3
GH_CONFIG_DIR=/config/gh
GIT_CONFIG_GLOBAL=/config/git/config
JJ_CONFIG=/config/jj/config.toml
HISTFILE=/config/shell/bash_history
GOPATH=/cache/go  GOMODCACHE=/cache/go/pkg/mod  GOCACHE=/cache/go/build
CARGO_HOME=/cache/cargo  RUSTUP_HOME=/opt/rustup
UV_CACHE_DIR=/cache/uv  UV_PYTHON_INSTALL_DIR=/cache/uv/python
NPM_CONFIG_CACHE=/cache/npm  NPM_CONFIG_PREFIX=/opt/npm-global  AUTO_UPDATE_PREFIX=/cache/npm-global
FNM_DIR=/cache/fnm
SHELL=/bin/bash  DISABLE_AUTOUPDATER=1
CHROME_PATH=/usr/bin/chromium  PUPPETEER_SKIP_DOWNLOAD=1
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
T3CODE_HOST=0.0.0.0  T3CODE_PORT=3773
T3CODE_CLOUDFLARED_PATH=/usr/local/bin/cloudflared
PATH=/cache/npm-global/bin:/opt/npm-global/bin:/usr/local/go/bin:/opt/cargo/bin:/cache/go/bin:/cache/fnm/aliases/default/bin:$PATH
```

PATH order matters: `/usr/local/bin/node` (image) comes before fnm's default alias,
so t3 and claude never pick up a project Node.

SSH: `/config/ssh` symlinked to `/home/code/.ssh` by the entrypoint (ssh has no
config-dir env var). Same for `/config/shell/bashrc.d` sourced from `.bashrc`.

## entrypoint.sh

Root half:
1. `groupmod`/`usermod` `code` to `PGID`/`PUID` if they differ.
2. `mkdir -p` every `/config/*` and `/cache/*` subdir; chown `/config` and `/cache`
   to `PUID:PGID` when not writable by `code`. Never chown the workspace, only warn.
3. `exec gosu code "$0" "$@"`.

User half:
1. Symlink `/config/ssh` -> `~/.ssh` (0700), touch git config.
1b. fnm: remove dangling links under `$FNM_DIR/node-versions/*/installation`, then link
    `$FNM_DIR/node-versions/v$NODE_VERSION/installation -> /opt/node/v$NODE_VERSION/installation`. If no `default`
    alias exists, `fnm default $NODE_VERSION`. Image Node shows up in `fnm ls` and a
    rebuild with a newer Node re-links automatically.
2. `register-mcp` (skips if already registered).
2b. `update-tools`: apply `AUTO_UPDATE` to the `/cache/npm-global` overlay, or empty it.
3. Map `T3_TELEMETRY=0` to `T3CODE_TELEMETRY_ENABLED=false` and `T3CODE_OTEL_SDK_DISABLED=true`.
4. If `$1` is `serve`: `exec t3 serve --host 0.0.0.0 --port 3773 "$WORKSPACE"`. Else `exec "$@"`.

No auto project add. No pairing print. No setup server.

## compose.yaml

```yaml
name: harness
services:
  harness:
    image: ${IMAGE:-ghcr.io/xaroth/harness:latest}
    build: .
    restart: unless-stopped
    environment:
      PUID: ${PUID:-1000}
      PGID: ${PGID:-1000}
      TZ: ${TZ:-UTC}
      WORKSPACE: ${WORKSPACE:-/workspace}
      PUBLIC_URL: ${PUBLIC_URL:-}
      T3_TELEMETRY: ${T3_TELEMETRY:-0}
    volumes:
      - config:/config
      - cache:/cache          # remove this line for an ephemeral cache
      - ${WORKSPACE_HOST:-./workspace}:${WORKSPACE:-/workspace}
    ports:
      - "127.0.0.1:${PORT:-3773}:3773"
    shm_size: 1gb             # chromium
    stop_grace_period: 30s
volumes:
  config:
  cache:
```

`.env.example`: `PUID`, `PGID`, `TZ`, `WORKSPACE_HOST`, `WORKSPACE`, `PORT`,
`PUBLIC_URL`, `IMAGE`, with a comment each.

## Helper scripts

- `pair [--ttl 30d]`: needs `PUBLIC_URL` or `--base-url`. Runs
  `t3 auth pairing create --base-url ... --json --ttl ...`, prints URL and QR via qrencode.
- `doctor`: versions of every tool, claude auth status, gh auth status, mount check
  for `/config` and `/cache` (named vs anonymous vs none), MCP registration status.
- `register-mcp`: `claude mcp add --scope user playwright -- playwright-mcp --headless
  --isolated --no-sandbox --executable-path /usr/bin/chromium` and
  `chrome-devtools -- chrome-devtools-mcp --headless --isolated --executablePath
  /usr/bin/chromium --chromeArg=--no-sandbox --chromeArg=--disable-dev-shm-usage`.
  Idempotent: checks `claude mcp list` first. `--remove` flag.

All helper scripts step down with gosu if run as root (`docker exec` lands as root).

## scripts/smoke-test.sh

Input: container name. Checks, each one line, exit on first failure:

1. Health endpoint answers within 90 s.
2. `--version` for: t3, claude, node, npm, go, rustc, cargo, clang, cmake, python3, uv,
   fnm, jj, gh (>= 2.81), git, git-lfs, cloudflared, ffmpeg, convert, psql, redis-cli,
   chromium, playwright-mcp, chrome-devtools-mcp.
3. `id -u` inside is `PUID`; `/config` and `/cache` writable by that uid.
4. `claude mcp list` mentions both servers.
5. MCP handshake: pipe an `initialize` JSON-RPC message into each MCP server, expect
   a response with `serverInfo`. Short timeout. No page load, no screenshot.
6. `prebuilds/linux-x64/pty.node` exists under the t3 platform package (terminals work).

## GitHub Actions

`build.yml`
- Triggers: PR, push to main, push tag `v*`, manual (`release` input), `workflow_call` (`ref` input).
- Steps: shellcheck, `docker compose config`, buildx build with GHA cache, `docker run`
  + `smoke-test.sh`, image size to the job summary.
- Publishes only when not called and the event is a push or a manual release:
  `latest` + `sha-<short>` on main, `vX.Y.Z` on a tag push. A push to main whose
  commit message contains "bump pinned versions" also computes the next patch tag,
  publishes it and pushes the git tag. Tags pushed with `GITHUB_TOKEN` trigger
  nothing, which is fine because the image is already up.
- Permissions: `contents: write` (tag), `packages: write`.

`bump.yml`
- Triggers: `schedule: cron '17 3 * * 1'` (Monday 03:17 UTC), `workflow_dispatch`.
- Job `bump`: `scripts/bump-versions.sh`, then `peter-evans/create-pull-request` on
  branch `bump/versions`, label `bump`, body = old -> new table. Same PR updated on
  later runs. If `vars.APP_ID` and `secrets.APP_PRIVATE_KEY` exist, the PR is opened
  with an App token (`actions/create-github-app-token`), so `build.yml` runs on it as
  a normal PR.
- Jobs `verify` and `report`, fallback when no App is configured: call `build.yml`
  with `ref: bump/versions`, then comment pass/fail, image size and run link on the
  PR. Needed because PRs opened with `GITHUB_TOKEN` fire no `pull_request` event.

## README outline

1. What it is, what's in the box, size.
2. Quickstart: clone, `cp .env.example .env`, `docker compose up -d`, `exec claude` to log in,
   `exec pair`, put reverse proxy in front.
3. Volumes: `/config`, `/cache`, workspace and the same-path rule for worktrees.
4. Updating: `docker compose pull && up -d`; how bump PRs work.
5. Security: loopback only, no sudo, gh token plaintext on volume, prefer fine-grained PAT.
6. Troubleshooting: uid mismatch, port in use, pairing link points at bridge IP.

## Order of work

1. Wipe folder, `jj git init --colocate`, set author in `.jj/repo/config.toml` and `.git/config`, LICENSE, `.gitignore`, `.dockerignore`.
2. Dockerfile. Build locally, check size with `docker image ls`.
3. entrypoint + helper scripts. Run compose up, log in to claude, verify `doctor`.
4. smoke-test.sh, run against local container.
5. Workflows. Can only be verified after push; write them, lint with `actionlint`.
6. README. Delete PLAN.md.
7. Commit with jj.

## Size budget

| Part | Est. |
| --- | --- |
| base + apt build tools | 600 MB |
| chromium + fonts | 450 MB |
| ffmpeg + imagemagick | 250 MB |
| Go | 250 MB |
| Rust minimal + clippy + rustfmt | 550 MB |
| clang/lld/cmake/gdb | 500 MB |
| t3 + claude + MCPs | 700 MB |
| rest | 150 MB |
| total | ~3.5 GB |

Hard limit 5 GB. Levers if over: drop gdb, drop fonts-noto-core, `rust-docs` already excluded by minimal profile.


## Verified against t3 0.0.44, claude-code 2.1.286, MCP servers (2026-09-30)

Checked by installing the packages, reading the binaries, and booting `t3 serve` locally.
Old-note pitfalls marked wrong or outdated are dropped from the design.

| Claim | Result | Effect on plan |
| --- | --- | --- |
| node-pty compiles from source, needs build tools | **Outdated.** t3 is now one 155 MB native binary; `node-pty` ships `prebuilds/linux-x64/pty.node` | build-essential stays only for cgo, python C extensions and node-gyp in projects. Smoke test checks the prebuilt file exists, nothing compiles |
| t3 needs node >= 22 | **Partly.** The `t3` npm package is a 4 KB node launcher around the binary. Node is still needed for claude-code's postinstall and both MCP servers (`>=20.19`) | Node tarball in `/usr/local`, pinned and bumped like Go. No node base image |
| claude-code is a node app | **Outdated.** npm postinstall copies a 231 MB native binary over the stub; no node process at runtime | Must not `--ignore-scripts`. Set `DISABLE_AUTOUPDATER=1` so it never tries to replace itself in `/opt` |
| `.claude.json` lands outside `~/.claude` | **Confirmed**, but `CLAUDE_CONFIG_DIR` moves it: test showed `.claude.json`, `backups/`, `projects/` all under the dir, nothing in `$HOME` | `CLAUDE_CONFIG_DIR=/config/claude` in image ENV. t3 also honours and forwards it |
| t3 reads PATH from a login shell | **Confirmed.** `$SHELL -ilc`, 5 s timeout, falls back to `/bin/bash`; result is merged with the inherited PATH, inherited entries kept | Set `SHELL=/bin/bash`, ship `.bash_profile` that sources `.bashrc`. fnm's alias dir goes last in PATH |
| gh must be >= 2.81 | **Confirmed.** Literal string in binary. Trixie ships 2.46, GitHub apt has 2.102 | GitHub apt repo, version asserted at build |
| Pairing URL uses the bridge IP | **Confirmed.** `t3 pair` prints the bound host and says so. `t3 auth pairing create --base-url X --ttl 30d --json` returns a `pairUrl` on X | `pair` script wraps the latter plus qrencode |
| t3 downloads cloudflared itself | **Confirmed.** Hardcoded 2026.5.2 unless `T3CODE_CLOUDFLARED_PATH` is set | Ship 2026.9.3, set the env var |
| preview_* tools need a desktop client | **Confirmed.** Server error text says so and tells the agent to use Playwright | Both MCP servers in image |
| t3 uses the OS keyring | **Wrong for us.** Only for reading Cursor tokens on macOS | Nothing to do |
| Absolute paths in t3 state | **Confirmed by design.** `t3 project add <path>`, worktreePath fields in the schema | Same-path mount rule stays |
| `t3 update` exists | **Confirmed.** Downloads into `T3CODE_INSTALL_BIN_DIR` or PATH dirs | README: don't. Bump PRs are the update path |
| Telemetry | **New finding.** PostHog on by default (`T3CODE_TELEMETRY_ENABLED`, default true) plus OTel | `.env` knob `T3_TELEMETRY`, default `0`, sets `T3CODE_TELEMETRY_ENABLED=false` and `T3CODE_OTEL_SDK_DISABLED=true` |
| MCP flags | playwright-mcp: `--headless --isolated --executable-path`. chrome-devtools-mcp: `--headless --isolated --executablePath --chromeArg` | As in `register-mcp` |
| `claude mcp add --scope user` | **Confirmed** | As planned |
| `t3 serve` flags | `--host --port [cwd]`, `--auto-bootstrap-project-from-cwd` exists but is off by default | Entrypoint: `t3 serve --host 0.0.0.0 --port 3773 "$WORKSPACE"` |
| Debian trixie versions | chromium 154, ffmpeg 7.1, cmake 3.31, imagemagick 7.1.1 | Fine |
| npm payload | t3 220 MB, claude 231 MB, both MCPs 34 MB. Only the matching platform package is installed | ~490 MB, in budget |
| Docker in WSL | 29.8.1, compose 5.5.1 | Ready |

Unverified, will confirm during build: playwright-core 0.0.83 driving Debian's chromium 154
via `--executable-path` (dizys does this and tests it, so low risk).

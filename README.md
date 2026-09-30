# harness

A T3 Code server with Claude Code and common toolchains in one Docker image, published as `ghcr.io/xaroth/harness`. You run it on a box you own, put a TLS reverse proxy in front, and drive Claude Code from app.t3.codes or the T3 phone app. The image is about 3.5 GB, amd64 only.

What's in the box (pins are `ARG`s in the Dockerfile):

- Debian trixie-slim base
- t3 0.0.44, Claude Code 2.1.286
- Node 24.21.0 (corepack enabled), fnm 1.39.0
- @playwright/mcp 0.0.83, chrome-devtools-mcp 1.10.1, Debian chromium
- Go 1.27.1, Rust 1.98.1 (minimal profile, clippy, rustfmt)
- Python 3 (Debian) and uv 0.12.21
- jj 0.45.1, git, git-lfs, gh (GitHub apt repo, at least 2.81.0)
- cloudflared 2026.9.3
- From Debian: build-essential, clang, lld, cmake, gdb, jq, ripgrep, fd, sqlite3, ffmpeg, imagemagick, psql, redis-cli, qrencode

## Quickstart

```sh
git clone https://github.com/xaroth/harness.git
cd harness
cp .env.example .env
```

Edit `.env`. At minimum set `PUID`/`PGID` to your host user (`id -u`, `id -g`), `WORKSPACE_HOST` to the host directory with your repos, and `PUBLIC_URL` to the https URL your reverse proxy will serve.

```sh
docker compose up -d
docker compose exec -u code harness claude auth login
docker compose exec -u code harness gh auth login   # optional
docker compose exec harness pair
```

`claude auth login` is interactive. `docker compose exec` allocates a TTY by default; with plain `docker exec` you need `-it -u code`. Run it as `code` so the credentials in `/config` are owned by the right user. `pair`, `doctor` and `register-mcp` switch to `code` themselves.

The server listens on `127.0.0.1:3773` only. Point a TLS reverse proxy (Caddy, nginx, Traefik) at it, then open app.t3.codes or the phone app and paste the pairing link or scan the QR code. app.t3.codes connects from your device, so the server only needs to be reachable over https from that device. It does not need to be public; a LAN or tailnet address with a valid certificate works.

No projects are added automatically. t3 starts with `WORKSPACE` as its working directory.

## Volumes

| Mount | What lives there |
| --- | --- |
| `/config` (named volume `config`) | `claude/` (`CLAUDE_CONFIG_DIR`, including `.claude.json` and credentials), `t3/` (`T3CODE_HOME`, server state and pairing), `gh/` (`GH_CONFIG_DIR`), `git/config` (`GIT_CONFIG_GLOBAL`), `jj/config.toml` (`JJ_CONFIG`), `ssh/` (linked to `~/.ssh`), `shell/bash_history`, `shell/bashrc.d/*.sh` (sourced by interactive shells) |
| `/cache` (named volume `cache`) | `go/` (`GOPATH`, `GOMODCACHE`, `GOCACHE`), `cargo/` (`CARGO_HOME`), `uv/` (`UV_CACHE_DIR`, `UV_PYTHON_INSTALL_DIR`), `npm/` (`NPM_CONFIG_CACHE`), `fnm/` (`FNM_DIR`). Safe to delete. Remove the `cache` line in `compose.yaml` for an ephemeral cache |
| `WORKSPACE` | Bind mount of `WORKSPACE_HOST`. Default `./workspace` on the host, `/workspace` inside |

On start the entrypoint creates missing subdirectories and chowns `/config` and `/cache` to `PUID:PGID` when they are not writable. It never chowns a populated workspace, it only warns.

t3 stores absolute paths (projects, worktrees), and git worktrees record absolute paths too. If you use the same repos from the host and from the container, set `WORKSPACE` equal to `WORKSPACE_HOST` (for example both `/home/you/src`) so paths resolve on both sides.

## Node versions

The image Node lives in `/opt/node` and is first on `PATH`. At boot the entrypoint links it into fnm, so `fnm ls` lists it and `fnm current` reports it. It becomes the fnm default if none is set.

`fnm install 22` and similar install into `/cache/fnm` and survive restarts. Interactive terminals run fnm with `--use-on-cd`, so a `.nvmrc` or `.node-version` switches Node when you `cd` into a project.

t3, Claude Code and the MCP servers always run on the image Node, regardless of what fnm selects in a terminal.

## Browser MCPs

On first boot `register-mcp` adds two MCP servers to Claude Code at user scope, both headless against `/usr/bin/chromium`:

- `playwright` (`playwright-mcp --headless --isolated --no-sandbox`)
- `chrome-devtools` (`chrome-devtools-mcp --headless --isolated`)

Both render pages with Debian chromium 154. chrome-devtools `navigate_page` needs a `pageId`; call `list_pages` or `new_page` first. `shm_size: 1gb` in compose is for chromium. Remove both with `register-mcp --remove`.

## Helpers

Run with `docker compose exec harness <cmd>`.

- `pair [--base-url URL] [--ttl 30d] [--label NAME]`: creates a pairing link on `PUBLIC_URL` (or `--base-url`) and prints it with a QR code.
- `doctor`: tool versions, uid, mount types for `/config`, `/cache` and the workspace, claude and gh auth status, `fnm ls`, `claude mcp list`, health endpoint.
- `register-mcp [--remove]`: adds or removes both browser MCPs. Idempotent.

## Updating

```sh
docker compose pull && docker compose up -d
```

To stay on a version, set `IMAGE=ghcr.io/xaroth/harness:vX.Y.Z` in `.env`.

Do not run `t3 update` inside the container. Claude Code's auto-updater is disabled. New versions come from image updates.

How releases happen:

- `bump.yml` runs every Monday at 03:17 UTC and on manual trigger. `scripts/bump-versions.sh` runs one resolver per pin from `scripts/bump.d/<ARG>.sh` and rewrites the Dockerfile. To add a pin, add an `ARG` and a resolver with the same name. If anything changed it opens or updates one PR on `bump/versions`, labelled `bump`, with an old/new table.
- `build.yml` runs on PRs, pushes to main, `v*` tags and manual trigger. It shellchecks the scripts, builds, boots the image and runs the smoke test. On push it publishes `:latest` (main), `:vX.Y.Z` plus `:latest` (tags) and `:sha-<short>`.
- `release.yml` tags the next patch when a `bump` PR is merged. It can also be run manually with patch, minor or major.

Set a `BUMP_TOKEN` repository secret: a PAT with contents and pull-requests write. PRs and tags pushed with the default `GITHUB_TOKEN` do not trigger other workflows, so without it bump PRs get no CI and release tags build no image.

## Building locally

```sh
docker compose build
# or
docker build -t harness:dev .
```

Smoke test (36 checks: health, tool versions, uid, volume perms, MCP registration and handshake, node-pty prebuilt, Node on PATH, Claude config location):

```sh
docker run -d --name harness-smoke -e PUID=1000 -e PGID=1000 \
  -v smoke-config:/config -v smoke-cache:/cache --shm-size 1g harness:dev
scripts/smoke-test.sh harness-smoke
```

Checks live in `scripts/smoke.d/NN-name.sh` and run in order; the first failure stops the run. The test expects uid 1000.

## Security

- The port is bound to `127.0.0.1`. TLS and exposure are up to your reverse proxy.
- No sudo in the image. The agent can do anything the `code` user can do inside the container, including reading `/config` and everything in the workspace, and it has network access.
- `gh auth login` stores the token in plaintext in `/config/gh/hosts.yml`. Prefer a fine-grained PAT limited to the repos you need.
- Never mount the Docker socket. That hands the agent root on the host.
- Pairing links are credentials. Don't paste them anywhere shared. Use a short `--ttl` if in doubt.
- t3 telemetry (PostHog and OpenTelemetry) is off by default. `T3_TELEMETRY=1` turns it on.

## Troubleshooting

- Files in the workspace owned by the wrong uid: set `PUID`/`PGID` in `.env` to your host `id -u`/`id -g` and `docker compose up -d`.
- "workspace ... not writable by uid" in the logs: the bind mount is owned by someone else. Fix ownership on the host or change `PUID`/`PGID`.
- Port 3773 already in use: set `PORT` in `.env`.
- Pairing link shows a 172.x address: that is the container bridge IP from t3's banner. Use `pair` with `PUBLIC_URL` set.
- Claude says not logged in: `docker compose exec -u code harness claude auth login`. It needs a TTY (`-it` with plain `docker exec`).
- MCP tools missing in a thread: threads started before registration don't see them. Start a new thread.
- "no job control in this shell" lines in the logs are harmless. t3 probes a login shell to read `PATH`.

## License

MIT, see `LICENSE`.

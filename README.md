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
| `/cache` (named volume `cache`) | `go/` (`GOPATH`, `GOMODCACHE`, `GOCACHE`), `cargo/` (`CARGO_HOME`), `uv/` (`UV_CACHE_DIR`, `UV_PYTHON_INSTALL_DIR`), `npm/` (`NPM_CONFIG_CACHE`), `fnm/` (`FNM_DIR`), `npm-global/` (newer claude and t3 from `AUTO_UPDATE`). Safe to delete. Remove the `cache` line in `compose.yaml` for an ephemeral cache |
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

## Open in VS Code over SSH

t3's open-in-editor button only ever produces a `vscode://vscode-remote/ssh-remote+<host><path>` link, and it only offers it when something listens on port 22 inside the container. The host is the container hostname plus `.local`. An SMB mount cannot be targeted this way.

Opt in with `SSHD=1` in `.env`. The entrypoint then starts sshd on port 22, key auth only, user `code`, host key stored on the config volume. Put your public key in the config volume at `ssh/authorized_keys`:

```sh
docker compose exec -u code harness sh -c 'cat >> /config/ssh/authorized_keys' < ~/.ssh/id_ed25519.pub
```

Port 22 is published as `SSH_BIND:SSH_PORT` (default `127.0.0.1:2222`). Set `SSH_BIND=0.0.0.0` if VS Code runs on another machine. Then teach ssh where `harness.local` lives, in `~/.ssh/config` on the machine running VS Code:

```
Host harness.local
  HostName <server ip>
  Port 2222
  User code
```

No mDNS needed; VS Code Remote SSH resolves the name through that file. Paths in the link match because the workspace is mounted at the same path inside. Change `CONTAINER_HOSTNAME` to use a different name. ssh sessions get the same PATH and config env as the server does, via `/etc/profile.d`.

## OS keyring

Apps that store secrets through the Secret Service (libsecret, `zalando/go-keyring`, `keytar`) need a D-Bus session bus and a keyring daemon. Opt in with `KEYRING=1` in `.env`. The entrypoint then starts `dbus-daemon` on `unix:path=/run/user/<uid>/bus` and an unlocked `gnome-keyring-daemon`, and exports `DBUS_SESSION_BUS_ADDRESS` to t3, login shells and ssh sessions. `secret-tool` is installed for debugging.

The keyring password is the fixed string `harness`, and the keyring lives in the container filesystem, so it is lost when the container is recreated. Don't store real credentials in it.

## Helpers

Run with `docker compose exec harness <cmd>`.

- `pair [--base-url URL] [--ttl 30d] [--label NAME]`: creates a pairing link on `PUBLIC_URL` (or `--base-url`) and prints it with a QR code.
- `doctor`: tool versions, uid, mount types for `/config`, `/cache` and the workspace, claude and gh auth status, `fnm ls`, `claude mcp list`, health endpoint.
- `register-mcp [--remove]`: adds or removes both browser MCPs. Idempotent.
- `update-tools [--status]`: applies `AUTO_UPDATE` (see below), or shows image and overlay versions and which one is on `PATH`. The entrypoint runs it on every start.

## Updating

```sh
docker compose pull && docker compose up -d
```

To stay on a version, set `IMAGE=ghcr.io/xaroth/harness:vX.Y.Z` in `.env`.

Do not run `t3 update` inside the container. Claude Code's auto-updater is disabled. New versions come from image updates, or from `AUTO_UPDATE` below.

### Updating claude and t3 on start

Claude Code and t3 release often. To pick up new versions without waiting for an image, set `AUTO_UPDATE` in `.env`:

```sh
AUTO_UPDATE=claude,t3                  # latest of both
AUTO_UPDATE=claude,t3@preview          # any npm dist-tag
AUTO_UPDATE=claude@2.1.290             # pin, also to roll back
```

On every start the entrypoint runs `update-tools` before t3. For each listed tool it asks npm which version the spec resolves to. If the image already has it, nothing is installed. Otherwise it `npm install -g`s that version into `/cache/npm-global`, which is ahead of `/opt/npm-global` on `PATH`. The overlay survives restarts and recreates, so a restart with nothing new costs about a second. A restart with an update adds a few seconds.

- A restart picks up new releases: `docker compose restart`. Claude starts per session, so new threads use the new Claude; t3 is the server and only changes on restart.
- If npm is unreachable, the current version stays. If an install fails, times out (`AUTO_UPDATE_TIMEOUT`, default 120 s) or the new binary does not run, the overlay copy is removed and the image copy is used.
- A tool removed from `AUTO_UPDATE` has its overlay copy removed on the next start. Once a pulled image catches up, the overlay copy is dropped too.
- `doctor` and `update-tools --status` show the image version, the overlay version, and which one is in use.

This runs a claude and t3 pair that CI did not test together, which the bump PR otherwise guarantees. If something breaks, pin the last good version or clear `AUTO_UPDATE` and restart.

How releases happen:

- `bump.yml` runs every Monday at 03:17 UTC and on manual trigger. `scripts/bump-versions.sh` runs one resolver per pin from `scripts/bump.d/<name>.sh` (for `ARG <NAME>_VERSION`) and rewrites the Dockerfile. If anything changed it opens or updates one PR on `bump/versions`, labelled `bump`, with an old/new table.
- With a GitHub App configured (below), the PR is opened as the App and `build.yml` runs on it like any other PR, so the checks show on the PR. Without one, a PR opened by a workflow triggers no CI, so `bump.yml` builds and smoke tests the branch itself and comments the result on the PR.
- You read the table and the checks, then merge. That is the only manual step.
- `build.yml` runs on PRs, pushes to main, `v*` tags and manual trigger. It shellchecks the scripts, builds, boots the image and runs the smoke test. On push to main it publishes `:latest` and `:sha-<short>`. If that push merged a bump PR, it also tags the next patch version and publishes `:vX.Y.Z`. Run it manually with `release` set to patch, minor or major for a release by hand.

GitHub App setup, optional, once:

1. Settings, Developer settings, GitHub Apps, New GitHub App. Any name, webhook off. Repository permissions: Contents read and write, Pull requests read and write.
2. Generate a private key and download it.
3. Install the App on this repository.
4. In the repository: variable `APP_ID` with the App ID, secret `APP_PRIVATE_KEY` with the key file contents.

To add a pin: an `ARG` in the Dockerfile, an install script, and a resolver in `scripts/bump.d/` with the matching name.

## Building locally

Each install step is a script in `docker/install/`, bind-mounted into its own `RUN` layer. Apt packages are listed in `docker/apt-packages.txt`. Add a tool by adding a script and a `RUN` line.

```sh
docker compose build
# or
docker build -t harness:dev .
```

Smoke test (46 checks: health, tool versions, uid, volume perms, MCP registration and handshake, node-pty prebuilt, Node on PATH, auto-update overlay, Claude config location, sshd, keyring):

```sh
docker run -d --name harness-smoke -e PUID=1000 -e PGID=1000 -e SSHD=1 -e KEYRING=1 \
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

#!/usr/bin/env bash
# Smoke test a running harness container. Usage: smoke-test.sh [container]
set -euo pipefail

c="${1:-harness-smoke}"
passed=0

ok() { echo "ok: $*"; passed=$((passed + 1)); }
fail() {
  echo "FAIL: $*"
  [[ -n "${out:-}" ]] && printf '%s\n' "$out" | tail -n 20 | sed 's/^/  /'
  echo "summary: $passed passed, 1 failed"
  exit 1
}
ux() { docker exec -u code "$c" "$@"; }

# check DESC CMD...: run CMD, pass on exit 0
check() {
  local desc="$1"
  shift
  if out="$("$@" 2>&1)"; then
    ok "$desc"
  else
    fail "$desc"
  fi
}

docker inspect "$c" >/dev/null 2>&1 || { out=""; fail "container $c not found"; }

# 1. health
deadline=$((SECONDS + 90))
until docker exec "$c" curl -fsS --max-time 4 -o /dev/null \
  http://127.0.0.1:3773/.well-known/t3/environment 2>/dev/null; do
  if [[ "$(docker inspect -f '{{.State.Running}}' "$c")" != true ]]; then
    out="$(docker logs --tail 20 "$c" 2>&1)"
    fail "container exited before health endpoint answered"
  fi
  if ((SECONDS >= deadline)); then
    out=""
    fail "health endpoint did not answer within 90s"
  fi
  sleep 2
done
ok "health endpoint answered after $((90 - (deadline - SECONDS)))s"

# 2. versions
for tool in t3 claude node npm rustc cargo clang cmake python3 uv fnm jj gh \
  git git-lfs cloudflared convert psql redis-cli chromium playwright-mcp \
  chrome-devtools-mcp; do
  check "$tool --version" ux "$tool" --version
done
# go and ffmpeg have no --version flag
check "go version" ux go version
check "ffmpeg -version" ux ffmpeg -version

out="$(ux gh --version 2>&1)" || fail "gh --version"
gh_ver="$(awk 'NR==1 {print $3}' <<<"$out")"
min=2.81.0
if [[ "$(printf '%s\n%s\n' "$min" "$gh_ver" | sort -V | head -n1)" == "$min" ]]; then
  ok "gh $gh_ver >= $min"
else
  fail "gh $gh_ver < $min"
fi

# 3. uid and volume perms
out="$(ux id -u 2>&1)" || fail "id -u"
if [[ "$out" == 1000 ]]; then ok "id -u is 1000"; else fail "id -u is $out, want 1000"; fi
for d in /config /cache; do
  check "$d writable by code" ux sh -c "f=$d/.smoke.\$\$ && touch \"\$f\" && rm \"\$f\""
done

# 4. MCP registration
out="$(ux timeout 60 claude mcp list 2>&1)" || fail "claude mcp list"
for s in playwright chrome-devtools; do
  if grep -q "$s" <<<"$out"; then ok "claude mcp list has $s"; else fail "claude mcp list missing $s"; fi
done

# 5. MCP handshake. stdio framing is one JSON message per line; read until
# serverInfo instead of closing stdin, which some servers treat as shutdown.
req='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
# shellcheck disable=SC2016 # expands inside the container
handshake='coproc S { "$@" 2>/dev/null; }
printf "%s\n" "$REQ" >&"${S[1]}"
while IFS= read -r -u "${S[0]}" line; do
  if [[ $line == *serverInfo* ]]; then echo "$line"; kill "$S_PID"; exit 0; fi
done
exit 1'
mcp() {
  local name="$1"
  shift
  check "$name MCP initialize returns serverInfo" \
    docker exec -i -u code -e REQ="$req" "$c" timeout 30 bash -c "$handshake" _ "$@"
}
mcp playwright playwright-mcp --headless --isolated --no-sandbox \
  --executable-path /usr/bin/chromium
mcp chrome-devtools chrome-devtools-mcp --headless --isolated \
  --executablePath /usr/bin/chromium --chromeArg=--no-sandbox \
  --chromeArg=--disable-dev-shm-usage

# 6. node-pty prebuilt
check "node-pty prebuilt pty.node present" ux test -f \
  /opt/npm-global/lib/node_modules/t3/node_modules/@t3code/t3-linux-x64/node_modules/node-pty/prebuilds/linux-x64/pty.node

# 7. image node wins in non-interactive shells
out="$(ux bash -c 'command -v node' 2>&1)" || fail "command -v node"
if [[ "$out" == /opt/node/current/bin/node ]]; then
  ok "node resolves to /opt/node/current/bin/node"
else
  fail "node resolves to $out, want /opt/node/current/bin/node"
fi

# 8. CLAUDE_CONFIG_DIR honoured. auth status exits non-zero when logged out.
ux claude auth status >/dev/null 2>&1 || true
check ".claude.json under /config/claude" ux test -f /config/claude/.claude.json

echo "summary: $passed passed, 0 failed"

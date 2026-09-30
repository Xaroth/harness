# shellcheck shell=bash
# image node must win in non-interactive shells, whatever fnm selects
out="$(ux bash -c 'command -v node' 2>&1)" || fail "command -v node"
if [[ "$out" == /opt/node/current/bin/node ]]; then
  ok "node resolves to /opt/node/current/bin/node"
else
  fail "node resolves to $out, want /opt/node/current/bin/node"
fi

# shellcheck shell=bash
out="$(ux timeout 60 claude mcp list 2>&1)" || fail "claude mcp list"
for s in playwright chrome-devtools; do
  if grep -q "$s" <<<"$out"; then ok "claude mcp list has $s"; else fail "claude mcp list missing $s"; fi
done

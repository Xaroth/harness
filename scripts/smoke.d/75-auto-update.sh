# shellcheck shell=bash
# AUTO_UPDATE is unset here, so the overlay stays empty and the image copies win
check "update-tools --status" ux update-tools --status
check "/cache/npm-global writable by code" ux test -w /cache/npm-global
for tool in claude t3; do
  out="$(ux bash -lc "command -v $tool" 2>&1)" || fail "command -v $tool"
  if [[ "$out" == "/opt/npm-global/bin/$tool" ]]; then
    ok "$tool resolves to the image copy"
  else
    fail "$tool resolves to $out, want /opt/npm-global/bin/$tool"
  fi
done
out="$(ux bash -lc 'printenv PATH' 2>&1)" || fail "login PATH"
if [[ ":$out:" == *:/cache/npm-global/bin:*/opt/npm-global/bin:* ]]; then
  ok "login PATH puts the overlay before /opt/npm-global/bin"
else
  fail "login PATH lacks overlay before image: $out"
fi

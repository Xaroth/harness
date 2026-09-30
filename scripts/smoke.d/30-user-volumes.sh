# shellcheck shell=bash
out="$(ux id -u 2>&1)" || fail "id -u"
if [[ "$out" == 1000 ]]; then ok "id -u is 1000"; else fail "id -u is $out, want 1000"; fi
for d in /config /cache; do
  check "$d writable by code" ux sh -c "f=$d/.smoke.\$\$ && touch \"\$f\" && rm \"\$f\""
done

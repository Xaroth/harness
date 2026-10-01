# shellcheck shell=bash
out="$(ux id -u 2>&1)" || fail "id -u"
if [[ "$out" == 1000 ]]; then ok "id -u is 1000"; else fail "id -u is $out, want 1000"; fi
for d in /config /cache; do
  check "$d writable by code" ux sh -c "f=$d/.smoke.\$\$ && touch \"\$f\" && rm \"\$f\""
done
# entrypoint mkdir -p runs as root, so an unlisted parent dir comes out root-owned.
# sshd host keys are root-owned on purpose.
bad="$(ux find /config /cache -maxdepth 3 -path /config/ssh/host_keys -prune -o -type d ! -writable -print 2>&1)"
if [[ -z "$bad" ]]; then ok "all dirs under /config and /cache writable by code"; else fail "not writable by code: ${bad//$'\n'/ }"; fi

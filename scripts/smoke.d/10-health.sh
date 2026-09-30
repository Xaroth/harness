# shellcheck shell=bash
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

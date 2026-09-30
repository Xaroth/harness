# shellcheck shell=bash
# container is started with SSHD=1 in CI
check "sshd listening on 22" docker exec "$c" sh -c 'ss -ltn | grep -q ":22 "'
check "sshd host key on /config" ux test -f /config/ssh/host_keys/ssh_host_ed25519_key
# shellcheck disable=SC2016 # expands inside the container
check "login shell sees CLAUDE_CONFIG_DIR" ux env -i /bin/bash -lc 'test "$CLAUDE_CONFIG_DIR" = /config/claude'
# real key login from inside the container to its own sshd
# shellcheck disable=SC2016
check "ssh login as code gets env and PATH" ux sh -c '
  k=$(mktemp -u) && ssh-keygen -q -t ed25519 -N "" -f "$k" &&
  cat "$k.pub" >> /config/ssh/authorized_keys &&
  ssh -i "$k" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes \
    code@127.0.0.1 "test \"\$CLAUDE_CONFIG_DIR\" = /config/claude && command -v claude && command -v go"'

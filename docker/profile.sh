# shellcheck shell=sh
# Keep image toolchains on PATH after /etc/profile resets it.
for d in /cache/go/bin /opt/cargo/bin /usr/local/go/bin /opt/node/current/bin /opt/npm-global/bin \
  /cache/npm-global/bin; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH

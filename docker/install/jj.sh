#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"
curl -fsSL "https://github.com/jj-vcs/jj/releases/download/v${JJ_VERSION}/jj-v${JJ_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  | tar -xz -C "$tmp"
install -m 0755 "$tmp/jj" /usr/local/bin/jj
rm -rf "$tmp"
jj --version

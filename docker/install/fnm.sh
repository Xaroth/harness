#!/usr/bin/env bash
# Binary only. Versions live in /cache/fnm at runtime; the entrypoint links the image Node in.
set -euo pipefail
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/fnm.zip" "https://github.com/Schniz/fnm/releases/download/v${FNM_VERSION}/fnm-linux.zip"
unzip -q "$tmp/fnm.zip" -d "$tmp"
install -m 0755 "$tmp/fnm" /usr/local/bin/fnm
rm -rf "$tmp"
fnm --version

#!/usr/bin/env bash
set -euo pipefail
curl -fsSL -o /usr/local/bin/cloudflared \
  "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64"
chmod 0755 /usr/local/bin/cloudflared
cloudflared --version

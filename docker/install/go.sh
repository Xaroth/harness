#!/usr/bin/env bash
set -euo pipefail
curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -xz -C /usr/local
/usr/local/go/bin/go version

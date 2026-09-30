#!/usr/bin/env bash
set -euo pipefail
curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" \
  | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh
uv --version

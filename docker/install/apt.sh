#!/usr/bin/env bash
set -euo pipefail
apt-get update
grep -v '^\s*#' /tmp/apt-packages.txt | grep -v '^\s*$' \
  | xargs apt-get install -y --no-install-recommends
# Debian names it fdfind
ln -s /usr/bin/fdfind /usr/local/bin/fd
rm -rf /var/lib/apt/lists/*

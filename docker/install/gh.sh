#!/usr/bin/env bash
# gh from GitHub's apt repo. Trixie ships 2.46, t3 needs >= 2.81 for sign-in status.
set -euo pipefail
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list
apt-get update
apt-get install -y --no-install-recommends gh
rm -rf /var/lib/apt/lists/*
v="$(gh --version | awk 'NR==1{print $3}')"
dpkg --compare-versions "$v" ge "$GH_MIN_VERSION" || { echo "gh $v < $GH_MIN_VERSION" >&2; exit 1; }

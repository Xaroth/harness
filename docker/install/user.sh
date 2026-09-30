#!/usr/bin/env bash
set -euo pipefail
groupadd --gid 1000 code
useradd --uid 1000 --gid 1000 --create-home --home-dir /home/code --shell /bin/bash code
# useradd leaves the account locked ('!'), which sshd rejects even for key auth.
# '*' unlocks it without allowing any password.
usermod -p '*' code
mkdir -p /workspace
chown 1000:1000 /workspace

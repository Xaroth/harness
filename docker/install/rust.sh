#!/usr/bin/env bash
# Toolchain in /opt, owned by code so rustup can update it. Registry goes to /cache/cargo at runtime.
set -euo pipefail
export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo
curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path \
  --profile minimal --default-toolchain "$RUST_VERSION" -c clippy -c rustfmt
rm -rf /opt/cargo/registry /opt/cargo/git /opt/rustup/downloads /opt/rustup/tmp
chown -R 1000:1000 /opt/rustup /opt/cargo
/opt/cargo/bin/rustc --version
/opt/cargo/bin/cargo --version

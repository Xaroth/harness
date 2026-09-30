#!/usr/bin/env bash
. "$(dirname "$0")/_lib.sh"
fetch https://static.rust-lang.org/dist/channel-rust-stable.toml |
  awk '/^\[/ {in_rust = ($0 == "[pkg.rust]")}
       in_rust && !done && /^version = / {gsub(/"/, "", $3); print $3; done = 1}'

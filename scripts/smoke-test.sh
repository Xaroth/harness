#!/usr/bin/env bash
# Smoke test a running harness container. Checks live in smoke.d/NN-name.sh
# and run in name order; the first failure stops the run.
# Usage: smoke-test.sh [container]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
c="${1:-harness-smoke}"

# shellcheck source=scripts/smoke.d/_lib.sh
. "$here/smoke.d/_lib.sh"

docker inspect "$c" >/dev/null 2>&1 || { out=""; fail "container $c not found"; }

for f in "$here"/smoke.d/[0-9]*.sh; do
  # shellcheck source=/dev/null
  . "$f"
done

echo "summary: $passed passed, 0 failed"

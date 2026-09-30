#!/usr/bin/env bash
. "$(dirname "$0")/_lib.sh"
fetch https://nodejs.org/dist/index.json |
  jq -r '[.[] | select(.version | startswith("v24."))][0].version' | sed 's/^v//'

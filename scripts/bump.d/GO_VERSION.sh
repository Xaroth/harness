#!/usr/bin/env bash
. "$(dirname "$0")/_lib.sh"
fetch 'https://go.dev/VERSION?m=text' | awk 'NR == 1 {sub(/^go/, ""); print}'

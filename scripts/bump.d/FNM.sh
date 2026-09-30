#!/usr/bin/env bash
. "$(dirname "$0")/_lib.sh"
gh_latest Schniz/fnm | sed 's/^v//'

#!/usr/bin/env bash
# Rewrite pinned ARG versions in the Dockerfile to the latest upstream releases.
# One resolver per pin lives in bump.d/<name>.sh (ARG <NAME>_VERSION) and prints
# the new version. Files starting with _ are helpers, not resolvers.
# Usage: bump-versions.sh [--dry-run] [--file PATH]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
file="$here/../Dockerfile"
dry_run=0
while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --file)
      file="${2:?--file needs a path}"
      shift
      ;;
    -h | --help)
      sed -n '2,5s/^# //p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done
[[ -f "$file" ]] || { echo "no such file: $file" >&2; exit 1; }

rows=()
for script in "$here"/bump.d/[!_]*.sh; do
  name="$(basename "$script" .sh)_VERSION"
  old="$(sed -n "s/^ARG $name=\([^[:space:]]*\).*/\1/p" "$file" | awk 'NR == 1')"
  if [[ -z "$old" ]]; then
    echo "ARG $name not found in $file" >&2
    exit 1
  fi
  new="$("$script")"
  # guard against error pages or "null" from jq ending up in the Dockerfile
  if [[ ! "$new" =~ ^[0-9][0-9A-Za-z.+-]*$ ]]; then
    echo "bad upstream version for $name: '$new'" >&2
    exit 1
  fi
  if [[ "$old" != "$new" ]]; then
    rows+=("| $name | $old | $new |")
    ((dry_run)) || sed -i "s/^ARG $name=[^[:space:]]*/ARG $name=$new/" "$file"
  fi
done

if ((${#rows[@]})); then
  changed=true
  table="$(printf '%s\n' "| Pin | Old | New |" "| --- | --- | --- |" "${rows[@]}")"
else
  changed=false
  table="No version changes."
fi

printf '%s\n' "$table"
((dry_run)) && echo "(dry run, $file not modified)" >&2

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  delim="EOF_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  {
    echo "changed=$changed"
    echo "table<<$delim"
    printf '%s\n' "$table"
    echo "$delim"
  } >>"$GITHUB_OUTPUT"
fi

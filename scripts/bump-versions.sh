#!/usr/bin/env bash
# Rewrite pinned ARG versions in the Dockerfile to the latest upstream releases.
# Usage: bump-versions.sh [--dry-run] [--file PATH]
set -euo pipefail

file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Dockerfile"
dry_run=0
while (($#)); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --file)
      file="${2:?--file needs a path}"
      shift
      ;;
    -h | --help)
      sed -n '2,3s/^# //p' "$0"
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

fetch() { curl -fsSL --retry 3 --max-time 30 "$@"; }

gh_fetch() {
  local auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fetch -H "Accept: application/vnd.github+json" "${auth[@]}" "$@"
}

npm_latest() { fetch "https://registry.npmjs.org/${1/\//%2f}/latest" | jq -r .version; }
gh_latest() { gh_fetch "https://api.github.com/repos/$1/releases/latest" | jq -r .tag_name; }

latest() {
  case "$1" in
    NODE_VERSION)
      fetch https://nodejs.org/dist/index.json |
        jq -r '[.[] | select(.version | startswith("v24."))][0].version' | sed 's/^v//'
      ;;
    T3_VERSION) npm_latest t3 ;;
    CLAUDE_CODE_VERSION) npm_latest @anthropic-ai/claude-code ;;
    PLAYWRIGHT_MCP_VERSION) npm_latest @playwright/mcp ;;
    CHROME_DEVTOOLS_MCP_VERSION) npm_latest chrome-devtools-mcp ;;
    GO_VERSION) fetch 'https://go.dev/VERSION?m=text' | awk 'NR == 1 {sub(/^go/, ""); print}' ;;
    RUST_VERSION)
      fetch https://static.rust-lang.org/dist/channel-rust-stable.toml |
        awk '/^\[/ {in_rust = ($0 == "[pkg.rust]")}
             in_rust && !done && /^version = / {gsub(/"/, "", $3); print $3; done = 1}'
      ;;
    CLOUDFLARED_VERSION) gh_latest cloudflare/cloudflared ;;
    JJ_VERSION) gh_latest jj-vcs/jj | sed 's/^v//' ;;
    FNM_VERSION) gh_latest Schniz/fnm | sed 's/^v//' ;;
    UV_VERSION) gh_latest astral-sh/uv ;;
  esac
}

names=(NODE_VERSION T3_VERSION CLAUDE_CODE_VERSION PLAYWRIGHT_MCP_VERSION
  CHROME_DEVTOOLS_MCP_VERSION GO_VERSION RUST_VERSION CLOUDFLARED_VERSION
  JJ_VERSION FNM_VERSION UV_VERSION)

rows=()
for name in "${names[@]}"; do
  old="$(sed -n "s/^ARG $name=\([^[:space:]]*\).*/\1/p" "$file" | awk 'NR == 1')"
  if [[ -z "$old" ]]; then
    echo "ARG $name not found in $file" >&2
    exit 1
  fi
  new="$(latest "$name")"
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

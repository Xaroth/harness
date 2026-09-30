# shellcheck shell=bash
# Sourced by every bump.d script. Each script prints one version string.
set -euo pipefail

fetch() { curl -fsSL --retry 3 --max-time 30 "$@"; }

gh_fetch() {
  local auth=()
  [[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fetch -H "Accept: application/vnd.github+json" "${auth[@]}" "$@"
}

npm_latest() { fetch "https://registry.npmjs.org/${1/\//%2f}/latest" | jq -r .version; }
gh_latest() { gh_fetch "https://api.github.com/repos/$1/releases/latest" | jq -r .tag_name; }

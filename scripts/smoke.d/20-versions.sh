# shellcheck shell=bash
for tool in t3 claude node npm rustc cargo clang cmake python3 uv fnm jj gh \
  git git-lfs cloudflared convert psql redis-cli chromium playwright-mcp \
  chrome-devtools-mcp; do
  check "$tool --version" ux "$tool" --version
done
# go and ffmpeg have no --version flag
check "go version" ux go version
check "ffmpeg -version" ux ffmpeg -version

out="$(ux gh --version 2>&1)" || fail "gh --version"
gh_ver="$(awk 'NR==1 {print $3}' <<<"$out")"
min=2.81.0
if [[ "$(printf '%s\n%s\n' "$min" "$gh_ver" | sort -V | head -n1)" == "$min" ]]; then
  ok "gh $gh_ver >= $min"
else
  fail "gh $gh_ver < $min"
fi

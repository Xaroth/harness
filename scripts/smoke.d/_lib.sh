# shellcheck shell=bash
# Sourced by smoke-test.sh before each check file. Expects $c (container name).
passed=0

ok() { echo "ok: $*"; passed=$((passed + 1)); }
fail() {
  echo "FAIL: $*"
  [[ -n "${out:-}" ]] && printf '%s\n' "$out" | tail -n 20 | sed 's/^/  /'
  echo "summary: $passed passed, 1 failed"
  exit 1
}
ux() { docker exec -u code "$c" "$@"; }

# check DESC CMD...: run CMD, pass on exit 0
check() {
  local desc="$1"
  shift
  if out="$("$@" 2>&1)"; then
    ok "$desc"
  else
    fail "$desc"
  fi
}

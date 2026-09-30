# shellcheck shell=bash
# auth status exits non-zero when logged out but still writes .claude.json
ux claude auth status >/dev/null 2>&1 || true
check ".claude.json under /config/claude" ux test -f /config/claude/.claude.json

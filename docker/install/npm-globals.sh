#!/usr/bin/env bash
# t3, claude-code and both browser MCPs. Not --ignore-scripts: claude-code's
# postinstall copies its native binary in.
set -euo pipefail
export PATH="/opt/npm-global/bin:/opt/node/current/bin:$PATH" \
  NPM_CONFIG_PREFIX=/opt/npm-global NPM_CONFIG_CACHE=/tmp/npm-cache \
  PUPPETEER_SKIP_DOWNLOAD=1 PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
  CLAUDE_CONFIG_DIR=/tmp/claude-build DISABLE_AUTOUPDATER=1

npm install -g --no-fund --no-audit \
  "t3@${T3_VERSION}" \
  "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
  "chrome-devtools-mcp@${CHROME_DEVTOOLS_MCP_VERSION}"

# source maps and other platforms' prebuilds are dead weight
find /opt/npm-global -name '*.map' -type f -delete
find /opt/npm-global -type d -path '*/prebuilds/*' ! -path '*/prebuilds/linux-x64*' -prune -exec rm -rf {} +

t3 --version
claude --version
playwright-mcp --version
chrome-devtools-mcp --version

npm cache clean --force
rm -rf /tmp/npm-cache /tmp/claude-build /root/.npm /root/.t3 /root/.cache /root/.claude*
chown -R 1000:1000 /opt/npm-global

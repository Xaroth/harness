# shellcheck shell=bash
check "node-pty prebuilt pty.node present" ux test -f \
  /opt/npm-global/lib/node_modules/t3/node_modules/@t3code/t3-linux-x64/node_modules/node-pty/prebuilds/linux-x64/pty.node

# shellcheck shell=bash
# stdio framing is one JSON message per line; read until serverInfo instead of
# closing stdin, which some servers treat as shutdown.
req='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}'
# shellcheck disable=SC2016 # expands inside the container
handshake='coproc S { "$@" 2>/dev/null; }
printf "%s\n" "$REQ" >&"${S[1]}"
while IFS= read -r -u "${S[0]}" line; do
  if [[ $line == *serverInfo* ]]; then echo "$line"; kill "$S_PID"; exit 0; fi
done
exit 1'
mcp() {
  local name="$1"
  shift
  check "$name MCP initialize returns serverInfo" \
    docker exec -i -u code -e REQ="$req" "$c" timeout 30 bash -c "$handshake" _ "$@"
}
mcp playwright playwright-mcp --headless --isolated --no-sandbox \
  --executable-path /usr/bin/chromium
mcp chrome-devtools chrome-devtools-mcp --headless --isolated \
  --executablePath /usr/bin/chromium --chromeArg=--no-sandbox \
  --chromeArg=--disable-dev-shm-usage

#!/usr/bin/env bash
# mcp-pin: pin an MCP server's tool manifest the day you approve it, and refuse
# to run against a manifest that has drifted since. A lockfile for tools.
#
#   mcp-pin [-f lockfile] [-n name] [-t seconds] pin   -- <server command> [args]
#   mcp-pin [-f lockfile] [-n name] [-t seconds] check -- <server command> [args]
#   mcp-pin [-f lockfile] [-n name] [-t seconds] show  -- <server command> [args]
#
#   -f, --lockfile  JSON lockfile holding one entry per server (default: mcp-pin.lock)
#   -n, --name      entry name in the lockfile (default: basename of the server command)
#   -t, --timeout   seconds to wait for tools/list (default: 20)
#
# The server is spawned over stdio, sent initialize, notifications/initialized and
# tools/list, and killed. Every tool's name, description and inputSchema is
# canonicalized (sorted keys, sorted by name) and hashed with SHA-256.
#
# Exit: 0 manifest matches the lockfile (or pin/show succeeded); 1 DRIFT;
#       2 bad usage; 3 server gave no tools/list answer or jq is missing;
#       4 check with no lockfile entry for this server.
set -euo pipefail

lockfile="mcp-pin.lock"; name=""; timeout=20
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--lockfile) lockfile="$2"; shift 2 ;;
    -n|--name)     name="$2"; shift 2 ;;
    -t|--timeout)  timeout="$2"; shift 2 ;;
    pin|check|show) mode="$1"; shift ;;
    --) shift; break ;;
    *) echo "mcp-pin: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ -n "${mode:-}" ] && [ $# -gt 0 ] || {
  echo "usage: mcp-pin [-f lockfile] [-n name] [-t seconds] pin|check|show -- <server command> [args]" >&2; exit 2; }
command -v jq >/dev/null || { echo "mcp-pin: jq is required" >&2; exit 3; }
if command -v sha256sum >/dev/null; then sha() { sha256sum | cut -d' ' -f1; }
else sha() { shasum -a 256 | cut -d' ' -f1; }; fi
[ -n "$name" ] || name="$(basename "$1")"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mcp-pin.XXXXXX")"
srv_pid=""
cleanup() {
  [ -n "$srv_pid" ] && kill "$srv_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

# Talk to the server. stdin stays open (sleep) long enough for it to answer;
# most stdio servers exit the moment stdin closes.
{
  printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"mcp-pin","version":"0.1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  sleep "$timeout"
} | "$@" >"$tmp/out" 2>"$tmp/err" &
srv_pid=$!

deadline=$(( $(date +%s) + timeout ))
until grep -q '"id": *2' "$tmp/out" 2>/dev/null; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "mcp-pin: no tools/list answer within ${timeout}s" >&2
    sed 's/^/  server stderr: /' "$tmp/err" >&2
    exit 3
  fi
  sleep 0.2
done
kill "$srv_pid" 2>/dev/null; srv_pid=""

# Canonical manifest: one object per tool, sorted keys, sorted by name.
if ! jq -c 'select(.id == 2) | .result.tools // empty' "$tmp/out" 2>/dev/null \
     | jq -S -c 'map({name, description, inputSchema}) | sort_by(.name)' >"$tmp/tools" \
   || [ ! -s "$tmp/tools" ] || [ "$(cat "$tmp/tools")" = "null" ]; then
  echo "mcp-pin: tools/list answered but carried no tools array" >&2; exit 3
fi
server_info="$(jq -c 'select(.id == 1) | .result.serverInfo // {}' "$tmp/out" | head -1)"
digest="$(sha <"$tmp/tools")"
count="$(jq 'length' "$tmp/tools")"

case "$mode" in
  show)
    jq -r '.[] | "\(.name)\t\(.description // "" | .[0:72])"' "$tmp/tools"
    echo "tools: $count  sha256: $digest"
    ;;
  pin)
    [ -f "$lockfile" ] || echo '{}' >"$lockfile"
    jq --arg n "$name" --arg d "$digest" --argjson t "$(cat "$tmp/tools")" \
       --argjson s "${server_info:-{\}}" --arg c "$*" --arg when "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.[$n] = {command: $c, server: $s, pinned_at: $when, sha256: $d, tools: $t}' \
       "$lockfile" >"$tmp/lock" && mv "$tmp/lock" "$lockfile"
    echo "pinned $name: $count tools, sha256 $digest -> $lockfile"
    ;;
  check)
    if ! jq -e --arg n "$name" '.[$n]' "$lockfile" >"$tmp/entry" 2>/dev/null; then
      echo "mcp-pin: no entry '$name' in $lockfile; run pin first" >&2; exit 4
    fi
    pinned="$(jq -r '.sha256' "$tmp/entry")"
    if [ "$pinned" = "$digest" ]; then
      echo "OK $name: $count tools, sha256 $digest matches $(jq -r '.pinned_at' "$tmp/entry")"
      exit 0
    fi
    echo "DRIFT $name: manifest changed since $(jq -r '.pinned_at' "$tmp/entry")"
    jq -r --argjson now "$(cat "$tmp/tools")" '
      .tools as $was
      | ($was | map({key: .name, value: .}) | from_entries) as $w
      | ($now | map({key: .name, value: .}) | from_entries) as $n
      | (($n | keys) - ($w | keys) | map("  + added:   " + .)),
        (($w | keys) - ($n | keys) | map("  - removed: " + .)),
        ([($w | keys)[] | select($n[.] != null and $n[.] != $w[.])]
          | map("  ~ changed: " + . + (if $n[.].description != $w[.].description then " (description)" else " (inputSchema)" end)))
      | .[]' "$tmp/entry"
    exit 1
    ;;
esac

#!/usr/bin/env bash
# Pin the fake server with mcp-pin, then drive a scripted session through mcp-guard.
# Expect: an honest session passes clean; the fourth tools/list and a repeated
# prompts/get after the third call are refused and the guard exits 1.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
guard="$here/../mcp-guard.sh"; pin="$here/../../mcp-pin/mcp-pin.sh"; srv="$here/fake-server.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
lock="$tmp/mcp-pin.lock"; fail=0
rpc() { local p="${3:-}"; [ -n "$p" ] || p="{}"; printf '{"jsonrpc":"2.0","id":%s,"method":"%s","params":%s}\n' "$1" "$2" "$p"; }
init() { rpc 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}'
         printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'; }
call() { rpc "$1" tools/call '{"name":"summarize","arguments":{"text":"x"}}'; }
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected $3, got $2"; fail=1; fi; }

"$pin" -f "$lock" -t 5 pin -- "$srv" >/dev/null

# 1. Honest session: two calls, lists re-read, clean exit 0, nothing refused.
{ init; rpc 2 tools/list; call 3; call 4; rpc 5 tools/list; rpc 6 prompts/get '{"name":"s"}'; rpc 7 prompts/get '{"name":"s"}'; } \
  | "$guard" -f "$lock" -- "$srv" >"$tmp/o1" 2>"$tmp/e1"; st=$?
check "honest session exits 0" "$st" 0
check "honest session answers all 7 requests" "$(grep -c '"result"' "$tmp/o1")" 7

# 2. Deadbugz session: three calls, then the client re-reads the tool list.
{ init; rpc 2 tools/list; call 3; call 4; call 5; rpc 6 tools/list; call 7; } \
  | "$guard" -f "$lock" -- "$srv" >"$tmp/o2" 2>"$tmp/e2"; st=$?
check "drifted tools/list exits 1" "$st" 1
check "id 6 answered with an error" "$(jq -r 'select(.id == 6) | .error.code' "$tmp/o2")" -32001
check "rewritten description never reaches the client" "$(grep -c 'id_ed25519' "$tmp/o2")" 0
check "call 7 never answered" "$(jq -r 'select(.id == 7) | .id' "$tmp/o2")" ""
check "diff names the tool" "$(grep -c 'changed: summarize (description)' "$tmp/e2")" 1

# 3. Prompt drift inside one session.
{ init; rpc 2 prompts/get '{"name":"s"}'; call 3; call 4; call 5; rpc 6 prompts/get '{"name":"s"}'; } \
  | "$guard" -f "$lock" -- "$srv" >"$tmp/o3" 2>"$tmp/e3"; st=$?
check "drifted prompts/get exits 1" "$st" 1
check "prompt id 6 answered with an error" "$(jq -r 'select(.id == 6) | .error.code' "$tmp/o3")" -32001

# 4. No lock entry: refuse to start.
"$guard" -f "$lock" -n nope -- "$srv" </dev/null >/dev/null 2>&1; st=$?
check "missing lock entry exits 4" "$st" 4

exit "$fail"

#!/usr/bin/env bash
# mcp-guard: sit between an MCP client and a stdio server, forward everything, and
# check every tools/list answer against the mcp-pin lockfile on its way up. Prompts
# get a session pin: the first prompts/list or prompts/get answer for a given set of
# params is recorded, and a different answer later in the same session is drift.
# On drift the client gets a JSON-RPC error instead of the answer, the diff goes
# to stderr, and the server is killed. A lock checked on every call.
#
#   mcp-guard [-f lockfile] [-n name] -- <server command> [args]
#
#   -f, --lockfile  mcp-pin lockfile (default: mcp-pin.lock)
#   -n, --name      entry name in the lockfile (default: basename of the server command)
#
# Put it in your client config where the server command was:
#   "command": "mcp-guard", "args": ["-f", "/abs/path/mcp-pin.lock", "--", "npx", "some-server"]
#
# Exit: 0 clean shutdown; 1 DRIFT (server killed);
#       2 bad usage; 3 jq missing; 4 no lockfile entry for this server.
set -uo pipefail

lockfile="mcp-pin.lock"; name=""
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--lockfile) lockfile="$2"; shift 2 ;;
    -n|--name)     name="$2"; shift 2 ;;
    --) shift; break ;;
    *) echo "mcp-guard: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[ $# -gt 0 ] || { echo "usage: mcp-guard [-f lockfile] [-n name] -- <server command> [args]" >&2; exit 2; }
command -v jq >/dev/null || { echo "mcp-guard: jq is required" >&2; exit 3; }
if command -v sha256sum >/dev/null; then sha() { sha256sum | cut -d' ' -f1; }
else sha() { shasum -a 256 | cut -d' ' -f1; }; fi
[ -n "$name" ] || name="$(basename "$1")"
jq -e --arg n "$name" '.[$n].tools' "$lockfile" >/dev/null 2>&1 || {
  echo "mcp-guard: no entry '$name' in $lockfile; run mcp-pin pin first" >&2; exit 4; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/mcp-guard.XXXXXX")"
mkdir "$tmp/req" "$tmp/pin"
mkfifo "$tmp/in" "$tmp/out"
srv_pid=""; cli_pid=""
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() {
  exec 2>/dev/null  # the diff is already out; drop the shell's "Terminated" job notices
  [ -n "$cli_pid" ] && kill "$cli_pid" 2>/dev/null
  [ -n "$srv_pid" ] && kill "$srv_pid" 2>/dev/null
  rm -rf "$tmp"
}
trap cleanup EXIT

"$@" <"$tmp/in" >"$tmp/out" &
srv_pid=$!
exec 3>"$tmp/in" 4<&0

# Client -> server: remember each request's method and params by id, then forward.
# When the client hangs up, close the server's stdin and give it two seconds to go.
{ while IFS= read -r line; do
  rec="$(jq -c 'select(type == "object" and has("method") and has("id"))
    | {k: (.id | tojson | @uri), m: .method, p: (.params // {})}' <<<"$line" 2>/dev/null)"
  [ -n "$rec" ] && printf '%s\n' "$rec" >"$tmp/req/$(jq -r .k <<<"$rec")"
  printf '%s\n' "$line" >&3
done; exec 3>&-; sleep 2; kill "$srv_pid" 2>/dev/null; } <&4 &
cli_pid=$!
exec 3>&- 4<&-

refuse() {  # $1 = the server's line, $2 = reason; stdin = diff lines
  jq -c --arg m "mcp-guard: $2; server stopped" \
    '{jsonrpc: "2.0", id, error: {code: -32001, message: $m}}' <<<"$1"
  echo "mcp-guard: DRIFT $name: $2" >&2
  sed 's/^/  /' >&2
  exit 1
}

# Server -> client: check the answers that carry instructions for the model.
while IFS= read -r line; do
  jq -e 'type == "object"' <<<"$line" >/dev/null 2>&1 \
    || refuse '{}' "non-object message from server" </dev/null
  k="$(jq -r 'select(has("id") and has("result")) | .id | tojson | @uri' <<<"$line")"
  if [ -n "$k" ] && [ -f "$tmp/req/$k" ]; then
    method="$(jq -r .m "$tmp/req/$k")"
    case "$method" in
      tools/list)
        diff="$(jq -r --arg n "$name" --slurpfile L "$lockfile" '
          ($L[0][$n].tools | map({key: .name, value: .}) | from_entries) as $w
          | .result.tools // [] | .[] | {name, description, inputSchema}
          | select($w[.name] != .)
          | if $w[.name] == null then "+ added:   \(.name)"
            elif $w[.name].description != .description then "~ changed: \(.name) (description)"
            else "~ changed: \(.name) (inputSchema)" end' <<<"$line")"
        [ -z "$diff" ] || refuse "$line" "tools/list differs from $lockfile" <<<"$diff"
        ;;
      prompts/list|prompts/get)
        key="$(jq -S -c '[.m, .p]' "$tmp/req/$k" | sha)"
        got="$(jq -S -c '.result' <<<"$line" | sha)"
        if [ ! -f "$tmp/pin/$key" ]; then
          printf '%s\n' "$got" >"$tmp/pin/$key"
        elif [ "$(cat "$tmp/pin/$key")" != "$got" ]; then
          refuse "$line" "$method answer changed mid-session" \
            <<<"$(jq -c '.p' "$tmp/req/$k") was $(cut -c1-12 "$tmp/pin/$key"), now ${got:0:12}"
        fi
        ;;
    esac
    rm -f "$tmp/req/$k"
  fi
  printf '%s\n' "$line"
done <"$tmp/out"

wait "$srv_pid" 2>/dev/null
srv_pid=""
exit 0

#!/usr/bin/env bash
# fusebox.sh - run a command under wall-clock, token, and dollar ceilings.
# The wrapped command must append per-call token counts (one integer per line)
# to the file named in $FUSE_USAGE. When any fuse trips, the run is killed.
set -euo pipefail

MAX_SECONDS="${MAX_SECONDS:-900}"      # wall-clock fuse
MAX_TOKENS="${MAX_TOKENS:-500000}"     # token fuse
USD_PER_MTOK="${USD_PER_MTOK:-15}"     # blended price, dollars per million tokens
MAX_USD="${MAX_USD:-20}"               # dollar fuse
export FUSE_USAGE="${FUSE_USAGE:-$(mktemp)}"
: > "$FUSE_USAGE"

[ "$#" -ge 1 ] || { echo "usage: fusebox.sh <command...>"; exit 2; }

if command -v setsid >/dev/null 2>&1; then
  setsid "$@" &                        # own process group, so we can kill children
else
  set -m; "$@" & set +m                # macOS has no setsid; job control gives the same pgid
fi
run_pgid=$!
start=$(date +%s)

trip() { echo "FUSEBOX: BLOWN - $1"; kill -TERM -"$run_pgid" 2>/dev/null || true; exit 1; }

while kill -0 "$run_pgid" 2>/dev/null; do
  elapsed=$(( $(date +%s) - start ))
  tokens=$(awk '{s+=$1} END{print s+0}' "$FUSE_USAGE")
  usd=$(awk -v t="$tokens" -v p="$USD_PER_MTOK" 'BEGIN{printf "%.2f", t/1000000*p}')

  [ "$elapsed" -ge "$MAX_SECONDS" ] && trip "wall-clock ${elapsed}s >= ${MAX_SECONDS}s"
  [ "$tokens"  -ge "$MAX_TOKENS"  ] && trip "tokens ${tokens} >= ${MAX_TOKENS}"
  awk -v u="$usd" -v m="$MAX_USD" 'BEGIN{exit !(u+0 >= m+0)}' && trip "spend \$$usd >= \$$MAX_USD"
  sleep 2
done

wait "$run_pgid" 2>/dev/null || true
echo "FUSEBOX: run completed within all fuses (tokens=$(awk '{s+=$1} END{print s+0}' "$FUSE_USAGE"))"

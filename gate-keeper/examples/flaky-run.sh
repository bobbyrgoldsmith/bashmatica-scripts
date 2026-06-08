#!/usr/bin/env bash
#
# flaky-run.sh — a deliberately non-deterministic test runner, so `--example`
# can demonstrate the REPLAY check catching a coin-flip verdict.
#
# It alternates pass/fail across consecutive calls using a counter file:
# call 1 passes (exit 0), call 2 fails (exit 1), then it resets. gate-keeper
# runs it twice, sees pass/fail, and refuses to ratify.
set -u

COUNTER="${TMPDIR:-/tmp}/gate-keeper-flaky.count"

n=0
[[ -f "$COUNTER" ]] && n="$(cat "$COUNTER" 2>/dev/null || echo 0)"
n=$((n + 1))

if [[ "$n" -ge 2 ]]; then
  rm -f "$COUNTER"        # reset for the next independent run
  echo "FAIL: order-confirmation not visible (timeout)"
  exit 1
fi

printf '%s' "$n" > "$COUNTER"
echo "PASS: order confirmed"
exit 0

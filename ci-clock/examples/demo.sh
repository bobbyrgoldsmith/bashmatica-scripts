#!/usr/bin/env bash
# Replay the three late fires that produced Bashmatica! #30 (cron slot 22:15 UTC).
set -euo pipefail
cd "$(dirname "$0")/.."
for t in 1787800674 1787897201 1787974968; do
  echo "--- CI_CLOCK_NOW=$t ($(date -u -r "$t" 2>/dev/null || date -u -d "@$t"))"
  CI_CLOCK_NOW=$t ./ci-clock.sh 22:15 || true
  echo "--- same run with CI_CLOCK_MAX_LAG=14400"
  CI_CLOCK_NOW=$t CI_CLOCK_MAX_LAG=14400 ./ci-clock.sh 22:15 || echo "exit=$?"
  echo
done

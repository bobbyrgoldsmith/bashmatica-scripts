#!/usr/bin/env bash
# ci-clock - measure how late a scheduled GitHub Actions run fired, and stop a
# downstream check from blaming your pipeline for the scheduler's lag.
# usage: ci-clock.sh "HH:MM"   (the UTC cron slot, e.g. "22:15")
#   CI_CLOCK_WINDOW_SEC  base window the downstream check uses (default 10800 = 3h)
#   CI_CLOCK_MAX_LAG     seconds of lag that fails the run outright (default 0 = never)
#   CI_CLOCK_NOW         override the current epoch for local testing
# Writes CI_CLOCK_LAG_SEC, CI_CLOCK_WINDOW_SEC and CI_CLOCK_SLOT_EPOCH to $GITHUB_ENV
# (or stdout), and lag-sec / window-sec / slot-epoch to $GITHUB_OUTPUT when set.
set -euo pipefail

slot="${1:?usage: ci-clock.sh HH:MM (UTC)}"
case "$slot" in
  [0-9][0-9]:[0-9][0-9]) ;;
  *) echo "ci-clock: slot must be HH:MM (24h, UTC), got '$slot'" >&2; exit 2 ;;
esac
now="${CI_CLOCK_NOW:-$(date -u +%s)}"
base="${CI_CLOCK_WINDOW_SEC:-10800}"
max="${CI_CLOCK_MAX_LAG:-0}"

today=$(date -u -d "@$now" +%Y-%m-%d 2>/dev/null || date -u -r "$now" +%Y-%m-%d)
sched=$(date -u -d "$today $slot:00" +%s 2>/dev/null || date -u -j -f "%Y-%m-%d %H:%M:%S" "$today $slot:00" +%s)
# If the slot is still in the future today, the run we're in belongs to yesterday's slot.
if [ "$sched" -gt "$now" ]; then sched=$((sched - 86400)); fi

lag=$((now - sched))
printf 'ci-clock: slot %s UTC, fired %dh%02dm late (%ds)\n' "$slot" $((lag/3600)) $(((lag%3600)/60)) "$lag"

if [ "$max" -gt 0 ] && [ "$lag" -gt "$max" ]; then
  echo "::error::LATE CRON: GitHub ran the $slot slot ${lag}s late (limit ${max}s). This is scheduler lag, not a pipeline failure."
  exit 2
fi

# Widen the downstream window by the lag so "published in the last N hours" stays honest.
{
  echo "CI_CLOCK_LAG_SEC=$lag"
  echo "CI_CLOCK_WINDOW_SEC=$((base + lag))"
  echo "CI_CLOCK_SLOT_EPOCH=$sched"
} >> "${GITHUB_ENV:-/dev/stdout}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "lag-sec=$lag"
    echo "window-sec=$((base + lag))"
    echo "slot-epoch=$sched"
  } >> "$GITHUB_OUTPUT"
fi

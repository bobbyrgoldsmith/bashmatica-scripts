#!/usr/bin/env bash
# judgment-ratio.sh - honest audit of what your automation actually hands off.
# Ledger format (TSV): step_name <TAB> status <TAB> human_minutes_per_run
#   status: auto | supervised | rework
set -euo pipefail

LEDGER="${1:-pipeline.tsv}"
[[ -f "$LEDGER" ]] || { echo "usage: $0 <ledger.tsv>"; exit 1; }

awk -F'\t' '
  NF < 3 { next }
  { total++; minutes += $3 }
  $2 == "auto"       { auto++ }
  $2 == "supervised" { sup++; sup_min += $3 }
  $2 == "rework"     { rew++; rew_min += $3 }
  END {
    if (total == 0) { print "no steps found"; exit 1 }
    handsoff = auto / total * 100
    printf "Steps audited:     %d\n", total
    printf "Truly hands-off:   %d (%.0f%%)\n", auto, handsoff
    printf "Supervised:        %d\n", sup
    printf "Rework / re-run:   %d\n", rew
    printf "Human minutes/run: %d (%d supervising, %d reworking)\n", minutes, sup_min, rew_min
    print  "---"
    if (handsoff >= 80)      print "Verdict: genuinely automated. Spend the freed time on the hard 20%."
    else if (handsoff >= 50) print "Verdict: half-automated. The babysat half is your real cost center."
    else                     print "Verdict: you have a dashboard, not automation. The judgment never left."
  }
' "$LEDGER"

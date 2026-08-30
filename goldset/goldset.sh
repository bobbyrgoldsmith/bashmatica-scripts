#!/usr/bin/env bash
# goldset.sh - run a golden set of cases through a model and fail on any regression.
# Case file (TSV): id <TAB> grader(equals|contains|regex) <TAB> expected <TAB> prompt
set -euo pipefail

CASES="${1:?usage: goldset.sh <cases.tsv>}"
LLM="${LLM:-llm}"
pass=0; fail=0

while IFS=$'\t' read -r id grader expected prompt; do
  [ -z "${id:-}" ] && continue
  case "$id" in \#*) continue;; esac
  out="$(printf '%s' "$prompt" | "$LLM")"

  ok=0
  case "$grader" in
    equals)   [ "$(printf '%s' "$out" | tr -d '[:space:]')" = \
                "$(printf '%s' "$expected" | tr -d '[:space:]')" ] && ok=1 ;;
    contains) printf '%s' "$out" | grep -qF -- "$expected" && ok=1 ;;
    regex)    printf '%s' "$out" | grep -qE -- "$expected" && ok=1 ;;
    *) echo "unknown grader: $grader (case $id)"; exit 2 ;;
  esac

  if [ "$ok" = 1 ]; then
    pass=$((pass+1)); printf 'PASS  %s\n' "$id"
  else
    fail=$((fail+1)); printf 'FAIL  %s  expected[%s] %s\n' "$id" "$grader" "$expected"
    printf '      got: %s\n' "$(printf '%s' "$out" | head -c 120)"
  fi
done < "$CASES"

echo "---"
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ] || { echo "GOLDSET: regression detected. Change blocked."; exit 1; }
echo "GOLDSET: clean. Safe to ship this change."

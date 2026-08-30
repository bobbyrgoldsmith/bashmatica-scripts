#!/usr/bin/env bash
# holdstill.sh - probe an LLM's run-to-run variance on a fixed prompt.
# usage: holdstill.sh <prompt-file> [runs] [value-regex]
set -euo pipefail

PROMPT="${1:?usage: holdstill.sh <prompt-file> [runs] [value-regex]}"
RUNS="${2:-30}"
VALUE_RE="${3:-}"          # optional: a regex capturing the value that matters
LLM="${LLM:-llm}"          # any CLI that reads a prompt on stdin

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
for i in $(seq 1 "$RUNS"); do
  "$LLM" < "$PROMPT" > "$tmp/out.$i"
done

echo "runs:            $RUNS"
echo "unique outputs:  $(for f in "$tmp"/out.*; do cksum < "$f"; done | sort -u | wc -l | tr -d ' ')"

# First line number at which any two runs disagree.
diverge="$(paste -d'\n' "$tmp"/out.1 "$tmp"/out.2 >/dev/null 2>&1; \
  for i in $(seq 2 "$RUNS"); do diff <(cat "$tmp/out.1") <(cat "$tmp/out.$i") \
    | grep -m1 '^[0-9]' | sed 's/[^0-9].*//'; echo; done \
  | grep -E '^[0-9]+$' | sort -n | head -1)"
echo "first divergence: ${diverge:-none (all identical)}"

if [ -n "$VALUE_RE" ]; then
  echo "--- distribution of the value that matters ---"
  for i in $(seq 1 "$RUNS"); do
    grep -oE "$VALUE_RE" "$tmp/out.$i" | head -1
  done | sort | uniq -c | sort -rn
fi

#!/usr/bin/env bash
# log-triage.sh: read-only CI-log triage. Summarizes and classifies; never fixes.
set -euo pipefail

LOG="${1:?usage: log-triage.sh <logfile> [test-context]}"
CONTEXT="${2:-no test context provided}"
LLM="${LLM:-llm}"   # any CLI that reads a prompt on stdin (llm, claude -p, etc.)

# Bag and tag: keep error lines plus 3 lines of context, numbered, capped at 120.
slice="$(awk '
  tolower($0) ~ /error|fail|traceback|exception|assert|panic|fatal/ {
    for (i = NR - 3; i <= NR + 3; i++) keep[i] = 1
  }
  { line[NR] = $0 }
  END { for (i = 1; i <= NR; i++) if (keep[i]) printf "%d: %s\n", i, line[i] }
' "$LOG" | tail -n 120)"

prompt="$(cat <<EOF
You are triaging one failed CI run. You do not fix it and do not propose a fix.
Report only what the log supports.

Test context: $CONTEXT

Classify as exactly one of: flaky | infra | real_regression | insufficient_evidence
Rules:
- Cite the log line number(s) that justify the classification.
- If no line justifies one, answer insufficient_evidence.
- Do not invent line numbers, files, or values that are not in the log.

Output these fields only:
classification:
evidence_lines:
confidence: low | medium | high
summary: (one sentence, grounded in the cited lines)

Log slice (line-numbered):
$slice
EOF
)"

printf '%s' "$prompt" | "$LLM"

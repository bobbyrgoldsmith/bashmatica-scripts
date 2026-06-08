#!/usr/bin/env bash
#
# gate-keeper.sh — Refuse to let an agent-generated test count as a passing
# gate until it clears deterministic checks the authoring agent can't fake.
#
# An agent that writes a test, runs it, and reports green is the grader and the
# graded collapsed into one process. gate-keeper is the second key: a separate
# process, with its own logic, that ratifies (or refuses) the test before it is
# allowed to gate CI. Three checks, mapping onto the three ways an agent ships a
# passing test that proves nothing:
#
#   DENSITY    — assertion-density floor. A test that asserts (almost) nothing
#                relative to its length is a coverage prop, not a gate. FAIL.
#   INJECTION  — no-state-manipulation scan. page.evaluate / executeScript /
#                DOM mutation / storage overrides / request fulfillment that
#                arrange the conditions of the test's own success. Not every
#                such call is illegitimate, so this FLAGs for a human by
#                default (FAIL under --strict).
#   REPLAY     — independent double-replay. Run the test twice and refuse a
#                verdict that does not reproduce. A test that passes once and
#                fails once was never a gate; it was a coin flip the agent won
#                on the run it watched. FAIL.
#
# The agent proposes. gate-keeper disposes. The agent never holds both keys.
#
# Usage:
#   ./gate-keeper.sh --test <spec-file> --run "<command>"
#   ./gate-keeper.sh --test ./tests/checkout.spec.ts --run "npx playwright test checkout"
#   ./gate-keeper.sh --strict --test <spec-file> --run "<command>"   # INJECTION also fails
#   ./gate-keeper.sh --density 25 --test <spec-file> --run "<command>"  # 1 assertion per 25 lines
#   ./gate-keeper.sh --example
#
# Options:
#   --test <file>     The test/spec file to ratify (required, unless --example).
#   --run "<cmd>"     The command that runs that test. gate-keeper runs it twice
#                     and compares verdicts. Point it at an isolated runner for a
#                     true independent replay. Required unless --no-replay.
#   --density <N>     Assertion-density floor: at least 1 assertion per N lines.
#                     Default 25. Lower is stricter.
#   --strict          An INJECTION flag also refuses ratification.
#   --no-replay       Skip the replay check (static checks only). Honest about
#                     what it is: half a gate.
#   --example         Run against the bundled sample (low density + an injected
#                     state write + a non-deterministic runner). Demonstrates a
#                     NOT RATIFIED verdict end to end.
#
# Exit codes:
#   0 — RATIFIED. The test may count as a passing gate.
#   1 — NOT RATIFIED. At least one check refused it.
#   2 — usage / input error.
#
# Requires: bash 3.2+, GNU or BSD coreutils (grep, awk, sed)

set -uo pipefail

# Print only the contiguous leading comment block (the header doc), so the
# inline `# ----` section dividers further down never leak into --help.
usage() {
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
  exit "${1:-2}"
}

# ----------------------------------------------------------------------
# Parse args
# ----------------------------------------------------------------------
TEST_FILE=""
RUN_CMD=""
DENSITY_FLOOR=25
STRICT=0
DO_REPLAY=1
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --test)       TEST_FILE="${2:-}"; shift 2 ;;
    --run)        RUN_CMD="${2:-}"; shift 2 ;;
    --density)    DENSITY_FLOOR="${2:-}"; shift 2 ;;
    --strict)     STRICT=1; shift ;;
    --no-replay)  DO_REPLAY=0; shift ;;
    --example)
      TEST_FILE="$SELF_DIR/examples/checkout.spec.ts"
      RUN_CMD="$SELF_DIR/examples/flaky-run.sh"
      shift ;;
    -h|--help)    usage 0 ;;
    *)            echo "Unknown option: $1" >&2; usage 2 ;;
  esac
done

if [[ -z "$TEST_FILE" ]]; then
  echo "Error: no --test file given" >&2
  usage 2
fi
if [[ ! -f "$TEST_FILE" ]]; then
  echo "Error: test file not found: $TEST_FILE" >&2
  exit 2
fi
if ! printf '%s' "$DENSITY_FLOOR" | grep -qE '^[1-9][0-9]*$'; then
  echo "Error: --density must be a positive integer" >&2
  exit 2
fi
if [[ "$DO_REPLAY" -eq 1 && -z "$RUN_CMD" ]]; then
  echo "Error: --run is required for the replay check (or pass --no-replay)" >&2
  usage 2
fi

BASE="$(basename "$TEST_FILE")"
FAIL=0
FLAG=0

# ----------------------------------------------------------------------
# Check 1 — assertion-density floor
#
# Count lines that carry an assertion against total non-blank, non-comment
# lines. This is a heuristic by design: it catches the agent that confirms a
# page rendered without confirming it rendered correctly.
# ----------------------------------------------------------------------
ASSERTION_RE='expect\(|assert[A-Za-z_]*[ (]|\.should[.( ]|\.to\.(be|equal|have|include|contain)|toBe[A-Z]|toBe\(|toEqual\(|toContain\(|toMatch\(|toHave[A-Z]'

# Strip blank and comment-only lines so prose containing the word "assert"
# (in a // or # comment) never counts as an assertion, and never inflates the
# line denominator either.
strip_code() {
  grep -vE '^[[:space:]]*$' "$1" \
    | grep -vE '^[[:space:]]*(//|#|\*|/\*)'
}

STRIPPED="$(strip_code "$TEST_FILE")"
LINES="$(printf '%s\n' "$STRIPPED" | grep -cE '.' | tr -d ' ')"
ASSERTS="$(printf '%s\n' "$STRIPPED" | grep -cE "$ASSERTION_RE" | tr -d ' ')"

if [[ "$ASSERTS" -eq 0 ]]; then
  echo "DENSITY   $BASE: 0 assertions in $LINES lines (floor: 1 per $DENSITY_FLOOR)  FAIL"
  FAIL=$((FAIL + 1))
else
  # integer "1 per N": lines / asserts, rounded down
  PER=$((LINES / ASSERTS))
  if [[ "$PER" -gt "$DENSITY_FLOOR" ]]; then
    echo "DENSITY   $BASE: 1 assertion per $PER lines (floor: 1 per $DENSITY_FLOOR)  FAIL"
    FAIL=$((FAIL + 1))
  else
    echo "DENSITY   $BASE: 1 assertion per $PER lines (floor: 1 per $DENSITY_FLOOR)  OK"
  fi
fi

# ----------------------------------------------------------------------
# Check 2 — no-state-manipulation scan
#
# Patterns that arrange the conditions of a test's own success by reaching
# past the application layer. Flags for a human; only --strict refuses.
# ----------------------------------------------------------------------
INJECTION_RE='page\.evaluate(Handle)?\(|frame\.evaluate\(|page\.addScriptTag\(|\.execute(_)?(async_)?[sS]cript\(|document\.(querySelector|getElementById)\([^)]*\)\.(innerHTML|innerText|textContent|value|checked|style)[[:space:]]*=|document\.cookie[[:space:]]*=|(local|session)Storage\.(setItem|removeItem|clear)\(|page\.route\([^)]*fulfill|cy\.intercept\([^)]*reply'

INJ_HIT="$(grep -nE "$INJECTION_RE" "$TEST_FILE" | head -n1 || true)"
if [[ -n "$INJ_HIT" ]]; then
  INJ_LINE="${INJ_HIT%%:*}"
  if [[ "$STRICT" -eq 1 ]]; then
    echo "INJECTION $BASE: state manipulation on line $INJ_LINE  FAIL"
    FAIL=$((FAIL + 1))
  else
    echo "INJECTION $BASE: state manipulation on line $INJ_LINE  FLAG"
    FLAG=$((FLAG + 1))
  fi
else
  echo "INJECTION $BASE: no state manipulation found  OK"
fi

# ----------------------------------------------------------------------
# Check 3 — independent double-replay
#
# Run the test twice and compare verdicts. Disagreement is non-determinism:
# the verdict the agent reported was a coin flip. Both-fail is an honest,
# reproducible failure (still not a passing gate). Both-pass ratifies.
# ----------------------------------------------------------------------
if [[ "$DO_REPLAY" -eq 1 ]]; then
  set +e
  ( eval "$RUN_CMD" ) >/dev/null 2>&1; R1=$?
  ( eval "$RUN_CMD" ) >/dev/null 2>&1; R2=$?
  set -e 2>/dev/null || true

  V1="pass"; [[ "$R1" -ne 0 ]] && V1="fail"
  V2="pass"; [[ "$R2" -ne 0 ]] && V2="fail"

  if [[ "$V1" != "$V2" ]]; then
    echo "REPLAY    $BASE: $V1 / $V2 across 2 runs (non-deterministic)  FAIL"
    FAIL=$((FAIL + 1))
  elif [[ "$V1" == "fail" ]]; then
    echo "REPLAY    $BASE: fail / fail across 2 runs (reproducible failure)  FAIL"
    FAIL=$((FAIL + 1))
  else
    echo "REPLAY    $BASE: pass / pass across 2 runs (reproducible)  OK"
  fi
else
  echo "REPLAY    $BASE: skipped (--no-replay)  WARN"
fi

# ----------------------------------------------------------------------
# Verdict
# ----------------------------------------------------------------------
echo
if [[ "$FAIL" -gt 0 ]]; then
  echo "Verdict: NOT RATIFIED ($FAIL refusal(s), $FLAG flag(s))"
  exit 1
fi
if [[ "$FLAG" -gt 0 ]]; then
  echo "Verdict: RATIFIED WITH FLAGS ($FLAG flag(s) — read the flagged line(s) assuming the worst)"
  exit 0
fi
echo "Verdict: RATIFIED"
exit 0

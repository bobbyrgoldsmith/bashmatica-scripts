#!/usr/bin/env bash
set -euo pipefail

# mutant-check: Lightweight mutation testing for any language.
#
# Applies simple operator mutations to a source file one at a time,
# runs your test command after each, and reports which mutations your
# tests caught (killed) vs. missed (survived). Educational, not
# production-grade; use PIT, StrykerJS, or mutmut for real projects.
#
# Usage:
#   ./mutant-check.sh --source app.py --test "pytest tests/ -q"
#   ./mutant-check.sh --source utils.js --test "npm test"
#   ./mutant-check.sh --source handler.go --test "go test ./..."
#
# CI integration:
#   ./mutant-check.sh --quiet --source src/pricing.py --test "pytest"

# --- Configuration ---

SOURCE=""
TEST_CMD=""
QUIET=0
TIMEOUT="${MUTANT_CHECK_TIMEOUT:-30}"

# --- Mutation operators ---
# Delimiter is @ to avoid collisions with operators like ||
# Format: pattern@replacement@label@guard
# Guard is optional: "no_gte" means skip lines containing >= or <=

OPERATORS=(
  '===@!==@strict equality → strict inequality'
  '!==@===@strict inequality → strict equality'
  '==@!=@equality → inequality'
  '!=@==@inequality → equality'
  '>=@>@greater-or-equal → greater-than'
  '<=@<@less-or-equal → less-than'
  '>@>=@greater-than → greater-or-equal@no_gte'
  '<@<=@less-than → less-or-equal@no_gte'
  '&&@||@logical AND → logical OR'
  '||@&&@logical OR → logical AND'
  '++@--@increment → decrement'
  '--@++@decrement → increment'
  'true@false@boolean true → false'
  'false@true@boolean false → true'
  'return @return !@negate return value'
)

# --- Counters ---

MUTANTS_TOTAL=0
MUTANTS_KILLED=0
MUTANTS_SURVIVED=0
MUTANTS_TIMEOUT=0

# --- Functions ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] --source FILE --test COMMAND

Lightweight mutation testing. Applies operator mutations to a source file
one at a time, runs your test command after each, and reports which mutations
your tests caught vs. missed.

Required:
  --source FILE    Source file to mutate
  --test COMMAND   Test command to run (quoted)

Options:
  --timeout SECS   Max seconds per test run (default: $TIMEOUT)
  --quiet          Suppress detail output, non-zero exit on survivors
  -h, --help       Show this help message

Environment:
  MUTANT_CHECK_TIMEOUT    Max seconds per test run (default: 30)
  MUTANT_CHECK_SKIP=1     Skip all checks

Exit codes:
  0  All mutants killed (or MUTANT_CHECK_SKIP=1)
  1  Surviving mutant(s) detected
  2  Usage error
EOF
}

# Run test command with timeout, return exit code
run_tests() {
  local result=0
  if command -v timeout &>/dev/null; then
    timeout "$TIMEOUT" bash -c "$TEST_CMD" &>/dev/null 2>&1 || result=$?
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$TIMEOUT" bash -c "$TEST_CMD" &>/dev/null 2>&1 || result=$?
  else
    bash -c "$TEST_CMD" &>/dev/null 2>&1 || result=$?
  fi
  echo "$result"
}

# Apply mutations for one operator across the source file
run_mutation() {
  local file="$1" pattern="$2" replacement="$3" label="$4" guard="${5:-}"
  local line_num=0

  while IFS= read -r line; do
    line_num=$((line_num + 1))

    # Check if line contains the pattern (fixed string match)
    if [[ "$line" != *"$pattern"* ]]; then
      continue
    fi

    # Guard: skip lines with >= or <= when mutating bare > or <
    if [[ "$guard" == "no_gte" ]]; then
      if [[ "$line" == *">="* ]] || [[ "$line" == *"<="* ]]; then
        continue
      fi
    fi

    # Create the mutant by replacing first occurrence
    local mutant_line="${line/$pattern/$replacement}"

    # Skip if no change (pattern was part of a longer token)
    if [[ "$mutant_line" == "$line" ]]; then
      continue
    fi

    MUTANTS_TOTAL=$((MUTANTS_TOTAL + 1))

    # Write mutant to file (replace the specific line)
    cp "$file" "${file}.mutant"
    sed -i.tmp "${line_num}s/.*/${mutant_line//\//\\/}/" "$file" 2>/dev/null || {
      cp "${file}.mutant" "$file"
      rm -f "${file}.tmp"
      continue
    }
    rm -f "${file}.tmp"

    # Run tests
    local test_result
    test_result=$(run_tests)

    # Restore original
    cp "${file}.mutant" "$file"

    # Evaluate result
    if [[ "$test_result" -eq 124 ]] || [[ "$test_result" -eq 137 ]]; then
      MUTANTS_TIMEOUT=$((MUTANTS_TIMEOUT + 1))
      if [[ "$QUIET" -eq 0 ]]; then
        printf "  TIMEOUT  L%-4d  %s\n" "$line_num" "$label"
      fi
    elif [[ "$test_result" -ne 0 ]]; then
      MUTANTS_KILLED=$((MUTANTS_KILLED + 1))
      if [[ "$QUIET" -eq 0 ]]; then
        printf "  KILLED   L%-4d  %s\n" "$line_num" "$label"
      fi
    else
      MUTANTS_SURVIVED=$((MUTANTS_SURVIVED + 1))
      if [[ "$QUIET" -eq 0 ]]; then
        printf "  SURVIVED L%-4d  %s\n" "$line_num" "$label"
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        if [[ ${#trimmed} -gt 100 ]]; then
          trimmed="${trimmed:0:97}..."
        fi
        printf "           > %s\n" "$trimmed"
      fi
    fi
  done < "$file"
}

# --- Parse arguments ---

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -lt 2 ]] && { echo "Error: --source requires a file path"; exit 2; }
      SOURCE="$2"; shift 2 ;;
    --test)
      [[ $# -lt 2 ]] && { echo "Error: --test requires a command"; exit 2; }
      TEST_CMD="$2"; shift 2 ;;
    --timeout)
      [[ $# -lt 2 ]] && { echo "Error: --timeout requires a number"; exit 2; }
      TIMEOUT="$2"; shift 2 ;;
    --quiet)
      QUIET=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    -*)
      echo "Unknown option: $1"; usage; exit 2 ;;
    *)
      echo "Unexpected argument: $1"; usage; exit 2 ;;
  esac
done

# --- Validate inputs ---

if [[ -z "$SOURCE" ]]; then
  echo "Error: --source is required."
  echo ""
  usage
  exit 2
fi

if [[ -z "$TEST_CMD" ]]; then
  echo "Error: --test is required."
  echo ""
  usage
  exit 2
fi

if [[ ! -f "$SOURCE" ]]; then
  echo "Error: Source file not found: $SOURCE"
  exit 2
fi

# --- Allow skip ---

if [[ "${MUTANT_CHECK_SKIP:-0}" == "1" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "mutant-check: MUTANT_CHECK_SKIP=1, skipping checks."
  exit 0
fi

# --- Verify test command passes on unmodified source ---

if [[ "$QUIET" -eq 0 ]]; then
  echo "=============================================="
  echo " MUTANT-CHECK: Mutation testing $SOURCE"
  echo "=============================================="
  echo ""
  echo "  Test command: $TEST_CMD"
  echo "  Timeout: ${TIMEOUT}s per mutation"
  echo ""
  echo "  Verifying tests pass on unmodified source..."
fi

if ! bash -c "$TEST_CMD" &>/dev/null 2>&1; then
  echo "Error: Test command fails on unmodified source. Fix your tests first."
  exit 2
fi

if [[ "$QUIET" -eq 0 ]]; then
  echo "  Baseline: PASS"
  echo ""
  echo "  Running mutations..."
  echo ""
fi

# --- Run mutations ---

for op in "${OPERATORS[@]}"; do
  IFS='@' read -r pattern replacement label guard <<< "$op"
  run_mutation "$SOURCE" "$pattern" "$replacement" "$label" "${guard:-}"
done

# --- Cleanup ---

rm -f "${SOURCE}.mutant" "${SOURCE}.tmp"

# --- Summary ---

if [[ "$MUTANTS_TOTAL" -eq 0 ]]; then
  if [[ "$QUIET" -eq 0 ]]; then
    echo ""
    echo "  No mutation opportunities found in $SOURCE."
    echo "  This file may not contain operators that mutant-check targets."
  fi
  exit 0
fi

SCORE=0
if [[ "$MUTANTS_TOTAL" -gt 0 ]]; then
  SCORE=$(( (MUTANTS_KILLED * 100) / MUTANTS_TOTAL ))
fi

if [[ "$QUIET" -eq 0 ]]; then
  echo ""
  echo "=============================================="
  echo " SUMMARY"
  echo "=============================================="
  echo ""
  echo "  Source file:      $SOURCE"
  echo "  Mutants generated: $MUTANTS_TOTAL"
  echo "  Killed (caught):   $MUTANTS_KILLED"
  echo "  Survived (missed): $MUTANTS_SURVIVED"
  if [[ "$MUTANTS_TIMEOUT" -gt 0 ]]; then
    echo "  Timed out:         $MUTANTS_TIMEOUT"
  fi
  echo "  Mutation score:    ${SCORE}%"
  echo ""

  if [[ "$MUTANTS_SURVIVED" -gt 0 ]]; then
    echo "  Surviving mutants indicate test blind spots: the source"
    echo "  code changed, but no test noticed. These are gaps that"
    echo "  a coverage report would never surface."
    echo ""
  else
    echo "  All mutants killed. Your tests caught every operator"
    echo "  mutation that mutant-check applied to this file."
    echo ""
  fi
fi

if [[ "$MUTANTS_SURVIVED" -gt 0 ]]; then
  exit 1
fi
exit 0

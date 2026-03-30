#!/usr/bin/env bash
set -euo pipefail

# assertion-density-check: Scan test files and report the ratio of
# assertions to total lines. Flags files where coverage inflation
# is likely: lots of setup, minimal verification.
#
# A test file with 200 lines and 2 assertions is not a test.
# It is a coverage prop.
#
# Run against a directory:
#   ./assertion-density-check.sh ./tests
#
# CI integration:
#   ./assertion-density-check.sh --quiet --threshold 15 ./tests

# --- Configuration ---

# Maximum lines-per-assertion ratio before flagging (default: 20)
# A file with 1 assertion per 20+ lines is suspicious.
RATIO_THRESHOLD="${ASSERT_DENSITY_THRESHOLD:-20}"

# Minimum lines before a file is worth checking (skip tiny files)
MIN_LINES="${ASSERT_DENSITY_MIN_LINES:-10}"

# --- Test file globs ---

TEST_GLOBS=(
  "*.test.js"  "*.test.ts"  "*.test.jsx"  "*.test.tsx"
  "*.spec.js"  "*.spec.ts"  "*.spec.jsx"  "*.spec.tsx"
  "*_test.js"  "*_test.ts"  "*_test.py"   "*_test.go"
  "*.test.py"  "*.spec.py"
  "test_*.py"
  "*_test.rb"  "*_spec.rb"
)

# --- Assertion patterns by framework ---

ASSERTION_PATTERNS=(
  # Jest / Vitest / Jasmine / Mocha+Chai
  'expect\('
  '\.toBe\('
  '\.toEqual\('
  '\.toStrictEqual\('
  '\.toContain\('
  '\.toMatch\('
  '\.toThrow\('
  '\.toHaveLength\('
  '\.toHaveBeenCalled'
  '\.toHaveProperty\('
  '\.toBeNull\('
  '\.toBeTruthy\('
  '\.toBeFalsy\('
  '\.toBeDefined\('
  '\.toBeUndefined\('
  '\.toBeGreaterThan\('
  '\.toBeLessThan\('
  '\.resolves\.'
  '\.rejects\.'
  '\.should\('
  '\.should\.\w+'
  '\.to\.\w+'

  # Python unittest
  'self\.assert\w+\('
  'self\.fail\('

  # Python pytest
  'assert\s+'
  'pytest\.raises\('

  # Go stdlib
  't\.Error\('
  't\.Errorf\('
  't\.Fatal\('
  't\.Fatalf\('

  # Go testify
  'require\.\w+\('
  'assert\.\w+\('

  # Ruby RSpec
  'expect\(.*\)\.to\s'
  'expect\(.*\)\.not_to\s'

  # Generic
  'verify\('
  'check\('
)

# --- Custom patterns support ---

CUSTOM_PATTERNS_FILE="${ASSERT_DENSITY_PATTERNS:-}"

# --- Functions ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [DIRECTORY]

Scan test files for assertion density. Flags files where the ratio of
lines to assertions exceeds the threshold, indicating tests that inflate
coverage metrics without meaningful verification.

Options:
  --threshold N    Max lines-per-assertion ratio before flagging (default: $RATIO_THRESHOLD)
  --min-lines N    Skip files shorter than N lines (default: $MIN_LINES)
  --patterns FILE  Load additional assertion patterns from file
  --sort FIELD     Sort output by: ratio (default), assertions, lines, name
  --summary        Print summary statistics only
  --quiet          Suppress explanations, print only findings
  -h, --help       Show this help message

Environment:
  ASSERT_DENSITY_THRESHOLD   Lines-per-assertion ratio threshold (default: 20)
  ASSERT_DENSITY_MIN_LINES   Minimum file length to check (default: 10)
  ASSERT_DENSITY_PATTERNS    Path to custom assertion patterns file
  ASSERT_DENSITY_SKIP=1      Skip all checks

Exit codes:
  0  No issues found (or ASSERT_DENSITY_SKIP=1)
  1  Issue(s) detected
  2  Usage error
EOF
}

find_test_files() {
  local search_dir="$1"
  local find_args=()

  for glob in "${TEST_GLOBS[@]}"; do
    if [[ ${#find_args[@]} -gt 0 ]]; then
      find_args+=("-o")
    fi
    find_args+=("-name" "$glob")
  done

  find "$search_dir" -type f \( "${find_args[@]}" \) 2>/dev/null | \
    grep -v node_modules | \
    grep -v __pycache__ | \
    grep -v '\.git/' | \
    grep -v vendor/ | \
    grep -v dist/ | \
    sort || true
}

build_assertion_pattern() {
  local combined=""
  for p in "${ASSERTION_PATTERNS[@]}"; do
    if [[ -n "$combined" ]]; then
      combined="${combined}|${p}"
    else
      combined="$p"
    fi
  done

  if [[ -n "$CUSTOM_PATTERNS_FILE" && -f "$CUSTOM_PATTERNS_FILE" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(echo "$line" | xargs 2>/dev/null || echo "$line")"
      [[ -z "$line" ]] && continue
      combined="${combined}|${line}"
    done < "$CUSTOM_PATTERNS_FILE"
  fi

  echo "($combined)"
}

# --- Parse arguments ---

SEARCH_DIR=""
QUIET=0
SUMMARY_ONLY=0
SORT_BY="ratio"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold)
      [[ $# -lt 2 ]] && { echo "Error: --threshold requires a number"; exit 2; }
      RATIO_THRESHOLD="$2"
      shift 2
      ;;
    --min-lines)
      [[ $# -lt 2 ]] && { echo "Error: --min-lines requires a number"; exit 2; }
      MIN_LINES="$2"
      shift 2
      ;;
    --patterns)
      [[ $# -lt 2 ]] && { echo "Error: --patterns requires a file path"; exit 2; }
      CUSTOM_PATTERNS_FILE="$2"
      shift 2
      ;;
    --sort)
      [[ $# -lt 2 ]] && { echo "Error: --sort requires a field (ratio, assertions, lines, name)"; exit 2; }
      SORT_BY="$2"
      shift 2
      ;;
    --summary)
      SUMMARY_ONLY=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      usage
      exit 2
      ;;
    *)
      SEARCH_DIR="$1"
      shift
      ;;
  esac
done

if [[ -z "$SEARCH_DIR" ]]; then
  SEARCH_DIR="."
fi

if [[ ! -d "$SEARCH_DIR" ]]; then
  echo "Error: $SEARCH_DIR is not a directory"
  exit 2
fi

# --- Allow skip ---

if [[ "${ASSERT_DENSITY_SKIP:-0}" == "1" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "assertion-density-check: ASSERT_DENSITY_SKIP=1, skipping checks."
  exit 0
fi

# --- Find test files ---

TEST_FILES=$(find_test_files "$SEARCH_DIR")

if [[ -z "$TEST_FILES" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "assertion-density-check: No test files found in $SEARCH_DIR"
  exit 0
fi

FILE_COUNT=$(echo "$TEST_FILES" | wc -l | tr -d ' ')
ASSERT_PATTERN=$(build_assertion_pattern)

# --- Scan files ---

# Temporary file for results (cleaned up on exit)
RESULTS_FILE=$(mktemp)
trap 'rm -f "$RESULTS_FILE"' EXIT

TOTAL_ASSERTIONS=0
TOTAL_LINES=0
FILES_CHECKED=0
FILES_FLAGGED=0
ZERO_ASSERTION_FILES=0

while IFS= read -r file; do
  total_lines=$(wc -l < "$file" | tr -d ' ')

  # Skip tiny files
  if [[ "$total_lines" -lt "$MIN_LINES" ]]; then
    continue
  fi

  assertion_count=$(grep -cE "$ASSERT_PATTERN" "$file" 2>/dev/null || echo "0")
  FILES_CHECKED=$((FILES_CHECKED + 1))
  TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + assertion_count))
  TOTAL_LINES=$((TOTAL_LINES + total_lines))

  if [[ "$assertion_count" -eq 0 ]]; then
    ZERO_ASSERTION_FILES=$((ZERO_ASSERTION_FILES + 1))
    FILES_FLAGGED=$((FILES_FLAGGED + 1))
    echo "0|999999|${total_lines}|${assertion_count}|${file}" >> "$RESULTS_FILE"
  elif [[ "$total_lines" -gt 0 ]]; then
    ratio=$((total_lines / assertion_count))
    if [[ "$ratio" -gt "$RATIO_THRESHOLD" ]]; then
      FILES_FLAGGED=$((FILES_FLAGGED + 1))
      echo "1|${ratio}|${total_lines}|${assertion_count}|${file}" >> "$RESULTS_FILE"
    fi
  fi
done <<< "$TEST_FILES"

# --- Output ---

if [[ "$FILES_FLAGGED" -eq 0 ]]; then
  if [[ "$QUIET" -eq 0 ]]; then
    echo "assertion-density-check: All $FILES_CHECKED file(s) passed."
    echo "  Threshold: 1 assertion per $RATIO_THRESHOLD lines"
    echo "  Total assertions: $TOTAL_ASSERTIONS across $TOTAL_LINES lines"
  fi
  exit 0
fi

# Sort results
case "$SORT_BY" in
  ratio)      SORT_KEY="-t| -k2 -nr" ;;
  assertions) SORT_KEY="-t| -k4 -n"  ;;
  lines)      SORT_KEY="-t| -k3 -nr" ;;
  name)       SORT_KEY="-t| -k5"     ;;
  *)          SORT_KEY="-t| -k2 -nr" ;;
esac

# Print zero-assertion files
ZERO_FILES=$(grep "^0|" "$RESULTS_FILE" 2>/dev/null || true)
LOW_FILES=$(grep "^1|" "$RESULTS_FILE" 2>/dev/null | sort $SORT_KEY || true)

if [[ -n "$ZERO_FILES" && "$SUMMARY_ONLY" -eq 0 ]]; then
  echo "=============================================="
  echo " NO ASSERTIONS: Coverage props"
  echo "=============================================="
  echo ""
  while IFS='|' read -r _ _ lines asserts file; do
    echo "  $file"
    echo "    $lines lines, 0 assertions"
    echo ""
  done <<< "$ZERO_FILES"
  if [[ "$QUIET" -eq 0 ]]; then
    echo "  These files execute code but verify nothing. They inflate"
    echo "  coverage metrics without catching a single defect."
    echo ""
  fi
fi

# Print low-density files
if [[ -n "$LOW_FILES" && "$SUMMARY_ONLY" -eq 0 ]]; then
  echo "=============================================="
  echo " LOW DENSITY: Below threshold (1 per $RATIO_THRESHOLD lines)"
  echo "=============================================="
  echo ""
  while IFS='|' read -r _ ratio lines asserts file; do
    echo "  $file"
    echo "    $lines lines, $asserts assertion(s) (1 per $ratio lines)"
    echo ""
  done <<< "$LOW_FILES"
  if [[ "$QUIET" -eq 0 ]]; then
    echo "  These files have more setup than verification. A test file"
    echo "  that runs 200 lines of code and checks 2 things is measuring"
    echo "  execution, not correctness."
    echo ""
  fi
fi

# Summary
echo "=============================================="
echo " SUMMARY"
echo "=============================================="
echo ""
echo "  Files scanned:        $FILES_CHECKED"
echo "  Files flagged:        $FILES_FLAGGED"
echo "  Zero-assertion files: $ZERO_ASSERTION_FILES"
echo "  Total assertions:     $TOTAL_ASSERTIONS across $TOTAL_LINES lines"
if [[ "$TOTAL_LINES" -gt 0 && "$TOTAL_ASSERTIONS" -gt 0 ]]; then
  OVERALL_RATIO=$((TOTAL_LINES / TOTAL_ASSERTIONS))
  echo "  Overall density:      1 assertion per $OVERALL_RATIO lines"
fi
echo "  Threshold:            1 assertion per $RATIO_THRESHOLD lines"
echo ""

exit 1

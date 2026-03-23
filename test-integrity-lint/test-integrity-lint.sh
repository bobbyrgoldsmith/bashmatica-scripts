#!/usr/bin/env bash
set -euo pipefail

# test-integrity-lint: Scan test files for patterns that indicate
# state manipulation outside proper test fixtures.
#
# Catches AI-generated tests that game the metric (passing tests)
# instead of pursuing the goal (catching bugs). Flags direct DOM
# injection, missing assertions, and state overrides that bypass
# the application layer.
#
# Run against a directory:
#   ./test-integrity-lint.sh ./tests
#
# Run against the whole project:
#   ./test-integrity-lint.sh .
#
# CI integration:
#   ./test-integrity-lint.sh --ci ./tests
#
# Check assertion density only:
#   ./test-integrity-lint.sh --assertions-only --threshold 3 ./tests

# --- Configuration ---

# Minimum assertions per test file before flagging
ASSERTION_THRESHOLD="${TEST_LINT_THRESHOLD:-3}"

# Custom patterns file (one regex per line, # comments)
CUSTOM_PATTERNS_FILE="${TEST_LINT_PATTERNS:-}"

# Test file globs
TEST_GLOBS=(
  "*.test.js"  "*.test.ts"  "*.test.jsx"  "*.test.tsx"
  "*.spec.js"  "*.spec.ts"  "*.spec.jsx"  "*.spec.tsx"
  "*_test.js"  "*_test.ts"  "*_test.py"   "*_test.go"
  "*.test.py"  "*.spec.py"
  "test_*.py"
)

# --- State Injection Patterns ---
# These indicate direct browser/DOM manipulation that bypasses
# the application's own state management.

STATE_INJECTION_PATTERNS=(
  # Playwright/Puppeteer direct evaluation
  'page\.evaluate\('
  'page\.evaluateHandle\('
  'page\.addScriptTag\('
  'page\.addStyleTag\('
  'frame\.evaluate\('

  # Selenium executeScript
  '\.executeScript\('
  '\.executeAsyncScript\('
  'execute_script\('
  'execute_async_script\('

  # Direct DOM manipulation in test context
  'document\.querySelector\(.*\)\.(innerHTML|innerText|value|textContent|checked|disabled|style)\s*='
  'document\.getElementById\(.*\)\.(innerHTML|innerText|value|textContent|checked|disabled|style)\s*='
  'document\.cookie\s*='

  # Storage manipulation in test context
  'localStorage\.setItem\('
  'sessionStorage\.setItem\('
  'localStorage\.removeItem\('
  'sessionStorage\.removeItem\('
  'localStorage\.clear\('
  'sessionStorage\.clear\('

  # Window/global state override
  'window\.\w+\s*='
  'globalThis\.\w+\s*='

  # Fetch/XHR interception that returns hardcoded success
  'page\.route\(.*fulfill'
  'page\.setRequestInterception\('
  'cy\.intercept\(.*reply'
)

# --- Assertion Patterns ---
# Used to count whether test files contain meaningful verification.

ASSERTION_PATTERNS=(
  'expect\('
  'assert\('
  'assert\.\w+\('
  '\.should\('
  '\.to\.\w+'
  '\.toBe\('
  '\.toEqual\('
  '\.toContain\('
  '\.toHaveLength\('
  '\.toMatch\('
  '\.toThrow\('
  '\.toHaveBeenCalled'
  '\.resolves\.'
  '\.rejects\.'
  'self\.assert'
  'self\.assertEqual'
  'self\.assertTrue'
  'self\.assertFalse'
  'self\.assertIn\('
  'self\.assertRaises\('
  'assert_equal\('
  'assert_raises\('
  'require\.\w+\('     # Go testify
  'if.*t\.Error\('     # Go stdlib
  't\.Fatal\('
)

# --- Functions ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [DIRECTORY]

Scan test files for patterns indicating state manipulation outside proper
test fixtures, and check assertion density.

Options:
  --threshold N      Minimum assertions per test file (default: $ASSERTION_THRESHOLD)
  --patterns FILE    Load additional state-injection patterns from file
  --assertions-only  Only check assertion density, skip state injection scan
  --injection-only   Only check state injection, skip assertion density
  --list             Print all active patterns and exit
  --ci               Exit with non-zero status on any finding (default behavior)
  --quiet            Suppress explanations, print only findings
  -h, --help         Show this help message

Environment:
  TEST_LINT_THRESHOLD   Assertion density threshold (default: 3)
  TEST_LINT_PATTERNS    Path to custom patterns file
  TEST_LINT_SKIP=1      Skip all checks

Exit codes:
  0  No issues found (or TEST_LINT_SKIP=1)
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
    sort
}

build_injection_pattern() {
  local combined=""
  for p in "${STATE_INJECTION_PATTERNS[@]}"; do
    if [[ -n "$combined" ]]; then
      combined="${combined}|${p}"
    else
      combined="$p"
    fi
  done

  local pfile="${1:-$CUSTOM_PATTERNS_FILE}"
  if [[ -n "$pfile" && -f "$pfile" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(echo "$line" | xargs 2>/dev/null || echo "$line")"
      [[ -z "$line" ]] && continue
      combined="${combined}|${line}"
    done < "$pfile"
  fi

  echo "($combined)"
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
  echo "($combined)"
}

list_patterns() {
  echo "State injection patterns:"
  echo ""
  for p in "${STATE_INJECTION_PATTERNS[@]}"; do
    echo "  $p"
  done

  local pfile="${1:-$CUSTOM_PATTERNS_FILE}"
  if [[ -n "$pfile" && -f "$pfile" ]]; then
    echo ""
    echo "Custom patterns from $pfile:"
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(echo "$line" | xargs 2>/dev/null || echo "$line")"
      [[ -z "$line" ]] && continue
      echo "  $line"
    done < "$pfile"
  fi

  echo ""
  echo "Assertion patterns (for density check):"
  echo ""
  for p in "${ASSERTION_PATTERNS[@]}"; do
    echo "  $p"
  done
}

# --- Parse arguments ---

SEARCH_DIR=""
QUIET=0
CHECK_INJECTION=1
CHECK_ASSERTIONS=1
EXTRA_PATTERNS_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold)
      [[ $# -lt 2 ]] && { echo "Error: --threshold requires a number"; exit 2; }
      ASSERTION_THRESHOLD="$2"
      shift 2
      ;;
    --patterns)
      [[ $# -lt 2 ]] && { echo "Error: --patterns requires a file path"; exit 2; }
      EXTRA_PATTERNS_FILE="$2"
      shift 2
      ;;
    --assertions-only)
      CHECK_INJECTION=0
      shift
      ;;
    --injection-only)
      CHECK_ASSERTIONS=0
      shift
      ;;
    --list)
      list_patterns "$EXTRA_PATTERNS_FILE"
      exit 0
      ;;
    --ci)
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

if [[ "${TEST_LINT_SKIP:-0}" == "1" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "test-integrity-lint: TEST_LINT_SKIP=1, skipping checks."
  exit 0
fi

# --- Find test files ---

TEST_FILES=$(find_test_files "$SEARCH_DIR")

if [[ -z "$TEST_FILES" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "test-integrity-lint: No test files found in $SEARCH_DIR"
  exit 0
fi

FILE_COUNT=$(echo "$TEST_FILES" | wc -l | tr -d ' ')
[[ "$QUIET" -eq 0 ]] && echo "test-integrity-lint: Scanning $FILE_COUNT test file(s) in $SEARCH_DIR"
echo ""

ISSUES_FOUND=0

# --- Check 1: State Injection ---

if [[ "$CHECK_INJECTION" -eq 1 ]]; then
  INJECTION_PATTERN=$(build_injection_pattern "$EXTRA_PATTERNS_FILE")
  INJECTION_HITS=""

  while IFS= read -r file; do
    matches=$(grep -nE "$INJECTION_PATTERN" "$file" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      INJECTION_HITS="${INJECTION_HITS}${file}\n${matches}\n\n"
    fi
  done <<< "$TEST_FILES"

  if [[ -n "$INJECTION_HITS" ]]; then
    ISSUES_FOUND=1
    echo "=============================================="
    echo " STATE INJECTION: Direct state manipulation"
    echo "=============================================="
    echo ""
    echo -e "$INJECTION_HITS" | while IFS= read -r line; do
      [[ -n "$line" ]] && echo "  $line"
    done
    if [[ "$QUIET" -eq 0 ]]; then
      echo ""
      echo "  These patterns indicate tests that manipulate browser or"
      echo "  application state directly rather than through proper fixtures."
      echo "  Verify each match: legitimate page.evaluate() calls exist,"
      echo "  but tests that inject state to force a passing result are"
      echo "  optimizing for the metric, not catching bugs."
      echo ""
    fi
  fi
fi

# --- Check 2: Assertion Density ---

if [[ "$CHECK_ASSERTIONS" -eq 1 ]]; then
  ASSERT_PATTERN=$(build_assertion_pattern)
  LOW_ASSERTION_FILES=""

  while IFS= read -r file; do
    total_lines=$(wc -l < "$file" | tr -d ' ')
    assertion_count=$(grep -cE "$ASSERT_PATTERN" "$file" 2>/dev/null || echo "0")

    if [[ "$assertion_count" -lt "$ASSERTION_THRESHOLD" && "$total_lines" -gt 10 ]]; then
      LOW_ASSERTION_FILES="${LOW_ASSERTION_FILES}  ${file} (${assertion_count} assertions, ${total_lines} lines)\n"
    fi
  done <<< "$TEST_FILES"

  if [[ -n "$LOW_ASSERTION_FILES" ]]; then
    ISSUES_FOUND=1
    echo "=============================================="
    echo " LOW ASSERTIONS: Possible confidence artifacts"
    echo "=============================================="
    echo ""
    echo -e "$LOW_ASSERTION_FILES"
    if [[ "$QUIET" -eq 0 ]]; then
      echo "  Files with fewer than $ASSERTION_THRESHOLD assertion(s) and more"
      echo "  than 10 lines of code. A test file with extensive setup but"
      echo "  minimal verification may be confirming structure rather than"
      echo "  catching defects."
      echo ""
      echo "  Adjust threshold: --threshold N or TEST_LINT_THRESHOLD=N"
      echo ""
    fi
  fi
fi

# --- Summary ---

if [[ "$ISSUES_FOUND" -eq 1 ]]; then
  exit 1
fi

[[ "$QUIET" -eq 0 ]] && echo "test-integrity-lint: No issues found. $FILE_COUNT file(s) checked."
exit 0

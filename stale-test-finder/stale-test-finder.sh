#!/usr/bin/env bash
set -euo pipefail

# stale-test-finder: Find test files that haven't kept pace with their
# source code. When QA capacity shrinks, test maintenance is one of the
# first things to slip. This script surfaces the rot before production does.
#
# A test file untouched for 6 months while its source changed last week
# is not a passing test. It is an outdated assumption about what that
# code does.
#
# Run against a directory:
#   ./stale-test-finder.sh ./src
#
# CI integration:
#   ./stale-test-finder.sh --quiet --threshold 90 ./src

# --- Configuration ---

# Days since last test modification before considering it stale
STALE_THRESHOLD="${STALE_TEST_THRESHOLD:-180}"

# Days since source modification to consider it recently changed
SOURCE_RECENT="${STALE_TEST_SOURCE_RECENT:-90}"

# Minimum test file size (lines) to check
MIN_LINES="${STALE_TEST_MIN_LINES:-5}"

# --- Test file globs ---

TEST_GLOBS=(
  "*.test.js"  "*.test.ts"  "*.test.jsx"  "*.test.tsx"
  "*.spec.js"  "*.spec.ts"  "*.spec.jsx"  "*.spec.tsx"
  "*_test.js"  "*_test.ts"  "*_test.py"   "*_test.go"
  "*.test.py"  "*.spec.py"
  "test_*.py"
  "*_test.rb"  "*_spec.rb"
)

# --- Directories to exclude ---

EXCLUDE_DIRS=(
  "node_modules"
  "__pycache__"
  ".git"
  "vendor"
  "dist"
  ".venv"
  "venv"
  "build"
  ".next"
)

# --- Functions ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [DIRECTORY]

Find test files that haven't been updated even though their corresponding
source files have changed. Surfaces the test-to-source drift that occurs
when QA capacity shrinks and test maintenance falls behind.

Options:
  --threshold DAYS     Days without modification before a test is stale (default: $STALE_THRESHOLD)
  --source-recent DAYS Consider source "recently changed" within this window (default: $SOURCE_RECENT)
  --min-lines N        Skip test files shorter than N lines (default: $MIN_LINES)
  --sort FIELD         Sort output by: staleness (default), source, name
  --summary            Print summary statistics only
  --quiet              Suppress explanations, non-zero exit on findings
  -h, --help           Show this help message

Environment:
  STALE_TEST_THRESHOLD       Days threshold for test staleness (default: 180)
  STALE_TEST_SOURCE_RECENT   Days threshold for recent source changes (default: 90)
  STALE_TEST_MIN_LINES       Minimum test file length to check (default: 5)
  STALE_TEST_SKIP=1          Skip all checks

Exit codes:
  0  No stale tests found (or STALE_TEST_SKIP=1)
  1  Stale test(s) detected
  2  Usage error
EOF
}

# Check if we're in a git repository
check_git() {
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Error: Not inside a git repository. stale-test-finder requires git history."
    exit 2
  fi
}

# Get the last modification timestamp (epoch seconds) from git log
git_last_modified() {
  local file="$1"
  git log -1 --format=%ct -- "$file" 2>/dev/null || echo "0"
}

# Calculate days since a timestamp
days_since() {
  local timestamp="$1"
  local now
  now=$(date +%s)
  if [[ "$timestamp" -eq 0 ]]; then
    echo "999999"
    return
  fi
  echo $(( (now - timestamp) / 86400 ))
}

# Find test files, excluding common non-source directories
find_test_files() {
  local search_dir="$1"
  local find_args=()
  local exclude_args=()

  # Build exclude arguments
  for dir in "${EXCLUDE_DIRS[@]}"; do
    exclude_args+=("-path" "*/${dir}/*" "-o")
  done

  # Build name match arguments
  for glob in "${TEST_GLOBS[@]}"; do
    if [[ ${#find_args[@]} -gt 0 ]]; then
      find_args+=("-o")
    fi
    find_args+=("-name" "$glob")
  done

  # Find files, excluding directories, matching test globs
  find "$search_dir" -type f \
    \( "${exclude_args[@]}" -false \) -prune -o \
    -type f \( "${find_args[@]}" \) -print 2>/dev/null | sort || true
}

# Attempt to find the source file for a given test file
# Tries multiple naming conventions
find_source_file() {
  local test_file="$1"
  local dir
  local base
  local candidates=()

  dir=$(dirname "$test_file")
  base=$(basename "$test_file")

  # Strategy 1: Remove .test. or .spec. from the middle
  # e.g., utils.test.ts -> utils.ts
  local direct
  direct=$(echo "$base" | sed -E 's/\.(test|spec)\./\./')
  candidates+=("$dir/$direct")

  # Strategy 2: Remove _test. suffix
  # e.g., utils_test.py -> utils.py, utils_test.go -> utils.go
  local underscore
  underscore=$(echo "$base" | sed -E 's/_test\./\./')
  candidates+=("$dir/$underscore")

  # Strategy 3: Remove test_ prefix (Python convention)
  # e.g., test_utils.py -> utils.py
  local prefix
  prefix=$(echo "$base" | sed -E 's/^test_//')
  candidates+=("$dir/$prefix")

  # Strategy 4: Look in src/ instead of test(s)/
  # e.g., tests/utils.test.ts -> src/utils.ts
  local src_dir
  src_dir=$(echo "$dir" | sed -E 's#(^|/)tests?(/|$)#\1src\2#')
  if [[ "$src_dir" != "$dir" ]]; then
    candidates+=("$src_dir/$direct")
    candidates+=("$src_dir/$underscore")
    candidates+=("$src_dir/$prefix")
  fi

  # Strategy 5: Look in lib/ instead of test(s)/
  local lib_dir
  lib_dir=$(echo "$dir" | sed -E 's#(^|/)tests?(/|$)#\1lib\2#')
  if [[ "$lib_dir" != "$dir" ]]; then
    candidates+=("$lib_dir/$direct")
    candidates+=("$lib_dir/$underscore")
    candidates+=("$lib_dir/$prefix")
  fi

  # Strategy 6: Look one directory up (common in Go projects)
  local parent_dir
  parent_dir=$(dirname "$dir")
  candidates+=("$parent_dir/$direct")
  candidates+=("$parent_dir/$underscore")

  # Return the first candidate that exists
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

# --- Parse arguments ---

SEARCH_DIR=""
QUIET=0
SUMMARY_ONLY=0
SORT_BY="staleness"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold)
      [[ $# -lt 2 ]] && { echo "Error: --threshold requires a number"; exit 2; }
      STALE_THRESHOLD="$2"
      shift 2
      ;;
    --source-recent)
      [[ $# -lt 2 ]] && { echo "Error: --source-recent requires a number"; exit 2; }
      SOURCE_RECENT="$2"
      shift 2
      ;;
    --min-lines)
      [[ $# -lt 2 ]] && { echo "Error: --min-lines requires a number"; exit 2; }
      MIN_LINES="$2"
      shift 2
      ;;
    --sort)
      [[ $# -lt 2 ]] && { echo "Error: --sort requires a field (staleness, source, name)"; exit 2; }
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

if [[ "${STALE_TEST_SKIP:-0}" == "1" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "stale-test-finder: STALE_TEST_SKIP=1, skipping checks."
  exit 0
fi

# --- Verify git ---

check_git

# --- Find test files ---

TEST_FILES=$(find_test_files "$SEARCH_DIR")

if [[ -z "$TEST_FILES" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "stale-test-finder: No test files found in $SEARCH_DIR"
  exit 0
fi

FILE_COUNT=$(echo "$TEST_FILES" | wc -l | tr -d ' ')

# --- Scan files ---

RESULTS_FILE=$(mktemp)
trap 'rm -f "$RESULTS_FILE"' EXIT

TESTS_CHECKED=0
TESTS_STALE=0
TESTS_NO_SOURCE=0
TESTS_OK=0

while IFS= read -r test_file; do
  # Skip tiny files
  total_lines=$(wc -l < "$test_file" | tr -d ' ')
  if [[ "$total_lines" -lt "$MIN_LINES" ]]; then
    continue
  fi

  TESTS_CHECKED=$((TESTS_CHECKED + 1))

  # Find corresponding source file
  source_file=""
  if ! source_file=$(find_source_file "$test_file"); then
    TESTS_NO_SOURCE=$((TESTS_NO_SOURCE + 1))
    continue
  fi

  # Get modification timestamps from git
  test_ts=$(git_last_modified "$test_file")
  src_ts=$(git_last_modified "$source_file")

  test_age=$(days_since "$test_ts")
  src_age=$(days_since "$src_ts")

  # Flag: test is stale AND source was recently changed
  if [[ "$test_age" -gt "$STALE_THRESHOLD" ]] && [[ "$src_age" -lt "$SOURCE_RECENT" ]]; then
    TESTS_STALE=$((TESTS_STALE + 1))
    echo "${test_age}|${src_age}|${test_file}|${source_file}" >> "$RESULTS_FILE"
  else
    TESTS_OK=$((TESTS_OK + 1))
  fi
done <<< "$TEST_FILES"

# --- Output ---

if [[ "$TESTS_STALE" -eq 0 ]]; then
  if [[ "$QUIET" -eq 0 ]]; then
    echo "stale-test-finder: All $TESTS_CHECKED test file(s) are current."
    echo "  Staleness threshold: $STALE_THRESHOLD days"
    echo "  Source recency window: $SOURCE_RECENT days"
    if [[ "$TESTS_NO_SOURCE" -gt 0 ]]; then
      echo "  Tests without matched source: $TESTS_NO_SOURCE (skipped)"
    fi
  fi
  exit 0
fi

# Sort results
case "$SORT_BY" in
  staleness) SORT_FLAGS="-t| -k1 -nr" ;;
  source)    SORT_FLAGS="-t| -k2 -n"  ;;
  name)      SORT_FLAGS="-t| -k3"     ;;
  *)         SORT_FLAGS="-t| -k1 -nr" ;;
esac

SORTED_RESULTS=$(sort $SORT_FLAGS "$RESULTS_FILE")

if [[ "$SUMMARY_ONLY" -eq 0 ]]; then
  echo "=============================================="
  echo " STALE TESTS: Source changed, tests did not"
  echo "=============================================="
  echo ""

  while IFS='|' read -r test_age src_age test_file source_file; do
    echo "  $test_file"
    echo "    Test last modified: ${test_age} days ago"
    echo "    Source ($source_file) last modified: ${src_age} days ago"
    echo "    Drift: $((test_age - src_age)) days"
    echo ""
  done <<< "$SORTED_RESULTS"

  if [[ "$QUIET" -eq 0 ]]; then
    echo "  These test files have not been updated to reflect changes in the"
    echo "  source code they cover. The test may still pass, but it is testing"
    echo "  assumptions about code that no longer matches those assumptions."
    echo ""
  fi
fi

# Summary
echo "=============================================="
echo " SUMMARY"
echo "=============================================="
echo ""
echo "  Test files scanned:         $TESTS_CHECKED"
echo "  Stale tests found:          $TESTS_STALE"
echo "  Tests without matched source: $TESTS_NO_SOURCE (skipped)"
echo "  Tests current:              $TESTS_OK"
echo "  Staleness threshold:        $STALE_THRESHOLD days"
echo "  Source recency window:       $SOURCE_RECENT days"
echo ""

exit 1

#!/usr/bin/env bash
set -euo pipefail

# weekday-audit: Scan text files for day-of-week / date mismatches.
#
# LLMs compute day names from dates via pattern matching, not calendar
# arithmetic. They get it wrong regularly — especially for future dates
# outside their training window. This script audits text files for every
# date-day pair it finds and flags mismatches.
#
# Scan a directory:
#   ./weekday-audit.sh ./reports
#
# Scan specific files:
#   ./weekday-audit.sh changelog.md meeting-notes.md
#
# CI integration:
#   ./weekday-audit.sh --quiet ./docs

# --- Configuration ---

QUIET=0
SUMMARY_ONLY=0
RECURSIVE=1

# --- Constants ---

D_LONG="Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday"
D_SHORT="Mon|Tue|Wed|Thu|Fri|Sat|Sun"
M_LONG="January|February|March|April|May|June|July|August|September|October|November|December"
M_SHORT="Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"

# --- Counters ---

FILES_SCANNED=0
PAIRS_CHECKED=0
MISMATCHES=0
FILES_WITH_ERRORS=0

# --- Functions ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <FILE|DIRECTORY>...

Scan text files for mismatches between day-of-week names and calendar dates.
Catches errors common in LLM-generated reports, briefs, and documentation.

Options:
  --no-recursive  Don't recurse into subdirectories
  --summary       Print summary statistics only
  --quiet         Suppress detail output, non-zero exit on findings
  -h, --help      Show this help message

Environment:
  WEEKDAY_AUDIT_SKIP=1   Skip all checks

Patterns detected:
  "Wednesday, April 9, 2026"    Day, Month DD, YYYY
  "April 9, 2026 (Wednesday)"   Month DD, YYYY (Day)
  "2026-04-09 (Wednesday)"      YYYY-MM-DD (Day)
  "Wednesday, 2026-04-09"       Day, YYYY-MM-DD

Exit codes:
  0  No mismatches found (or WEEKDAY_AUDIT_SKIP=1)
  1  Mismatch(es) detected
  2  Usage error
EOF
}

# Detect GNU vs BSD date
DATE_FLAVOR=""

detect_date_flavor() {
  if date --version &>/dev/null 2>&1; then
    DATE_FLAVOR="gnu"
  else
    DATE_FLAVOR="bsd"
  fi
}

# Get actual weekday name for a YYYY-MM-DD date
get_weekday() {
  local ymd="$1"
  if [[ "$DATE_FLAVOR" == "gnu" ]]; then
    date -d "$ymd" "+%A" 2>/dev/null || echo ""
  else
    date -j -f "%Y-%m-%d" "$ymd" "+%A" 2>/dev/null || echo ""
  fi
}

# Convert month name to two-digit number
month_num() {
  local m
  m=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$m" in
    january|jan)   echo "01" ;; february|feb)  echo "02" ;;
    march|mar)     echo "03" ;; april|apr)     echo "04" ;;
    may)           echo "05" ;; june|jun)      echo "06" ;;
    july|jul)      echo "07" ;; august|aug)    echo "08" ;;
    september|sep) echo "09" ;; october|oct)   echo "10" ;;
    november|nov)  echo "11" ;; december|dec)  echo "12" ;;
    *) echo "" ;;
  esac
}

# Normalize day name to full form
normalize_day() {
  local d
  d=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$d" in
    monday|mon)    echo "Monday" ;;    tuesday|tue)   echo "Tuesday" ;;
    wednesday|wed) echo "Wednesday" ;; thursday|thu)  echo "Thursday" ;;
    friday|fri)    echo "Friday" ;;    saturday|sat)  echo "Saturday" ;;
    sunday|sun)    echo "Sunday" ;;    *) echo "" ;;
  esac
}

# Validate a claimed day against a date. Prints "claimed|actual|ymd" on mismatch.
# Returns 0 on mismatch, 1 on match or invalid input.
check_pair() {
  local claimed="$1" ymd="$2"
  local normalized actual

  normalized=$(normalize_day "$claimed")
  [[ -z "$normalized" ]] && return 1

  actual=$(get_weekday "$ymd")
  [[ -z "$actual" ]] && return 1

  if [[ "$normalized" != "$actual" ]]; then
    echo "${normalized}|${actual}|${ymd}"
    return 0
  fi
  return 1
}

report_hit() {
  local file="$1" lnum="$2" line="$3" result="$4"
  local claimed actual ymd
  IFS='|' read -r claimed actual ymd <<< "$result"

  MISMATCHES=$((MISMATCHES + 1))

  [[ "$SUMMARY_ONLY" -eq 1 ]] && return 0

  printf "  %s:%d\n" "$file" "$lnum"
  printf "    Claims: %-11s  Actual: %-11s  Date: %s\n" "$claimed" "$actual" "$ymd"

  # Trim leading whitespace and truncate long lines
  local trimmed="${line#"${line%%[![:space:]]*}"}"
  [[ ${#trimmed} -gt 120 ]] && trimmed="${trimmed:0:117}..."
  printf "    > %s\n\n" "$trimmed"
}

# --- Pattern functions ---
# Each tries one regex pattern against a line. Returns 0 if a mismatch is found.

# Pattern 1: Day[,] Month DD[,] YYYY — e.g., "Wednesday, April 9, 2026"
try_dmy() {
  local file="$1" lnum="$2" line="$3"
  local p="(${D_LONG}|${D_SHORT})[,[:space:]]+(${M_LONG}|${M_SHORT})[[:space:]]+([0-9]{1,2})[,[:space:]]+([0-9]{4})"

  [[ "$line" =~ $p ]] || return 1

  local claimed="${BASH_REMATCH[1]}" month="${BASH_REMATCH[2]}"
  local day="${BASH_REMATCH[3]}" year="${BASH_REMATCH[4]}"
  local mn ymd result

  mn=$(month_num "$month")
  [[ -z "$mn" ]] && return 1

  printf -v ymd "%s-%s-%02d" "$year" "$mn" "$((10#$day))"
  PAIRS_CHECKED=$((PAIRS_CHECKED + 1))

  if result=$(check_pair "$claimed" "$ymd"); then
    report_hit "$file" "$lnum" "$line" "$result"
    return 0
  fi
  return 1
}

# Pattern 2: Month DD[,] YYYY (Day) — e.g., "April 9, 2026 (Wednesday)"
try_mdy_paren() {
  local file="$1" lnum="$2" line="$3"
  local p="(${M_LONG}|${M_SHORT})[[:space:]]+([0-9]{1,2})[,[:space:]]+([0-9]{4})[[:space:]]*\((${D_LONG}|${D_SHORT})\)"

  [[ "$line" =~ $p ]] || return 1

  local month="${BASH_REMATCH[1]}" day="${BASH_REMATCH[2]}"
  local year="${BASH_REMATCH[3]}" claimed="${BASH_REMATCH[4]}"
  local mn ymd result

  mn=$(month_num "$month")
  [[ -z "$mn" ]] && return 1

  printf -v ymd "%s-%s-%02d" "$year" "$mn" "$((10#$day))"
  PAIRS_CHECKED=$((PAIRS_CHECKED + 1))

  if result=$(check_pair "$claimed" "$ymd"); then
    report_hit "$file" "$lnum" "$line" "$result"
    return 0
  fi
  return 1
}

# Pattern 3: YYYY-MM-DD (Day) — e.g., "2026-04-09 (Wednesday)"
try_iso_paren() {
  local file="$1" lnum="$2" line="$3"
  local p="([0-9]{4})-([0-9]{2})-([0-9]{2})[[:space:]]*\((${D_LONG}|${D_SHORT})\)"

  [[ "$line" =~ $p ]] || return 1

  local year="${BASH_REMATCH[1]}" month="${BASH_REMATCH[2]}"
  local day="${BASH_REMATCH[3]}" claimed="${BASH_REMATCH[4]}"
  local ymd="${year}-${month}-${day}" result

  PAIRS_CHECKED=$((PAIRS_CHECKED + 1))

  if result=$(check_pair "$claimed" "$ymd"); then
    report_hit "$file" "$lnum" "$line" "$result"
    return 0
  fi
  return 1
}

# Pattern 4: Day[,] YYYY-MM-DD — e.g., "Wednesday, 2026-04-09"
try_day_iso() {
  local file="$1" lnum="$2" line="$3"
  local p="(${D_LONG}|${D_SHORT})[,[:space:]]+([0-9]{4})-([0-9]{2})-([0-9]{2})"

  [[ "$line" =~ $p ]] || return 1

  local claimed="${BASH_REMATCH[1]}" year="${BASH_REMATCH[2]}"
  local month="${BASH_REMATCH[3]}" day="${BASH_REMATCH[4]}"
  local ymd="${year}-${month}-${day}" result

  PAIRS_CHECKED=$((PAIRS_CHECKED + 1))

  if result=$(check_pair "$claimed" "$ymd"); then
    report_hit "$file" "$lnum" "$line" "$result"
    return 0
  fi
  return 1
}

# --- File scanning ---

scan_file() {
  local file="$1"
  local line_num=0
  local file_hits=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_num=$((line_num + 1))

    # Quick skip: line must plausibly contain a day name
    [[ "$line" =~ (Mon|Tue|Wed|Thu|Fri|Sat|Sun) ]] || continue

    # Try each pattern; stop at first match per line to avoid double-counting
    if try_dmy "$file" "$line_num" "$line"; then
      file_hits=$((file_hits + 1))
    elif try_mdy_paren "$file" "$line_num" "$line"; then
      file_hits=$((file_hits + 1))
    elif try_iso_paren "$file" "$line_num" "$line"; then
      file_hits=$((file_hits + 1))
    elif try_day_iso "$file" "$line_num" "$line"; then
      file_hits=$((file_hits + 1))
    fi
  done < "$file"

  FILES_SCANNED=$((FILES_SCANNED + 1))
  if [[ "$file_hits" -gt 0 ]]; then
    FILES_WITH_ERRORS=$((FILES_WITH_ERRORS + 1))
  fi
}

find_text_files() {
  local dir="$1"
  local name_args=( -name "*.md" -o -name "*.txt" -o -name "*.log" -o
    -name "*.html" -o -name "*.json" -o -name "*.yaml" -o
    -name "*.yml" -o -name "*.csv" -o -name "*.rst" -o
    -name "*.adoc" -o -name "*.org" -o -name "*.tex" )

  if [[ "$RECURSIVE" -eq 0 ]]; then
    find "$dir" -maxdepth 1 -type f \( "${name_args[@]}" \) 2>/dev/null | sort
  else
    find "$dir" \
      \( -name .git -o -name node_modules -o -name __pycache__ \
         -o -name vendor -o -name .venv -o -name venv \
         -o -name dist -o -name build -o -name .next \) -prune \
      -o -type f \( "${name_args[@]}" \) -print 2>/dev/null | sort
  fi
}

# --- Parse arguments ---

TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-recursive) RECURSIVE=0; shift ;;
    --summary)      SUMMARY_ONLY=1; shift ;;
    --quiet)        QUIET=1; SUMMARY_ONLY=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    -*)             echo "Unknown option: $1"; usage; exit 2 ;;
    *)              TARGETS+=("$1"); shift ;;
  esac
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "Error: No files or directories specified."
  echo ""
  usage
  exit 2
fi

# --- Allow skip ---

if [[ "${WEEKDAY_AUDIT_SKIP:-0}" == "1" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "weekday-audit: WEEKDAY_AUDIT_SKIP=1, skipping checks."
  exit 0
fi

# --- Detect date command ---

detect_date_flavor

# --- Scan targets ---

if [[ "$QUIET" -eq 0 ]] && [[ "$SUMMARY_ONLY" -eq 0 ]]; then
  echo "=============================================="
  echo " WEEKDAY AUDIT: Checking date-day consistency"
  echo "=============================================="
  echo ""
fi

for target in "${TARGETS[@]}"; do
  if [[ -f "$target" ]]; then
    scan_file "$target"
  elif [[ -d "$target" ]]; then
    while IFS= read -r f; do
      scan_file "$f"
    done < <(find_text_files "$target")
  else
    echo "Warning: $target not found, skipping." >&2
  fi
done

# --- Summary ---

if [[ "$QUIET" -eq 0 ]]; then
  echo "=============================================="
  echo " SUMMARY"
  echo "=============================================="
  echo ""
  echo "  Files scanned:          $FILES_SCANNED"
  echo "  Date-day pairs checked: $PAIRS_CHECKED"
  echo "  Mismatches found:       $MISMATCHES"
  echo "  Files with mismatches:  $FILES_WITH_ERRORS"
  echo ""

  if [[ "$MISMATCHES" -eq 0 ]]; then
    echo "  All date-day pairs are consistent."
    echo ""
  elif [[ "$SUMMARY_ONLY" -eq 0 ]]; then
    echo "  Day names were validated against your system's calendar."
    echo "  Mismatches indicate the text claims a different weekday"
    echo "  than the date actually falls on."
    echo ""
  fi
fi

[[ "$MISMATCHES" -gt 0 ]] && exit 1
exit 0

#!/usr/bin/env bash
set -euo pipefail

# unit-check: Validate unit-conversion claims against deterministic constants.
#
# LLMs emit unit conversions by pattern-matching tokens, not by computing
# them. They sometimes use full-precision constants (1 kg = 2.20462 lb)
# and sometimes use colloquial approximations (1 kg ≈ 2.2 lb). The bug
# isn't always wrongness — it's that the precision isn't pinned, and at
# tier thresholds (FedEx 1000-lb cutoff, regulatory tolerances) that
# variance is the production incident. This script scans text files for
# claimed conversions, recomputes them deterministically, and flags
# inaccuracies and threshold-crossing errors.
#
# Scan a directory:
#   ./unit-check.sh ./reports
#
# Scan specific files:
#   ./unit-check.sh shipping-manifest.md compliance-doc.txt
#
# CI integration with threshold:
#   ./unit-check.sh --ci --threshold lb:1000 ./shipping

# --- Configuration ---

QUIET=0
SUMMARY_ONLY=0
RECURSIVE=1
TOLERANCE_PCT="0.5"     # default: 0.5% relative tolerance
STRICT=0                # --strict sets TOLERANCE_PCT to 0.05
THRESHOLDS=()           # array of "UNIT:VALUE" strings

# --- Unit pattern unions (used in regex assembly) ---

# Each unit's match alternatives. Keep ordered: longest forms first so the
# regex engine prefers them over shorter alternatives.
U_KG="kilograms?|kgs?"
U_LB="pounds?|lbs?"
U_MI="miles?|mi"
U_KM="kilometres?|kilometers?|km"
U_FT="feet|foot|ft"
U_M="metres?|meters?|m"
U_GAL="gallons?|gal"
U_L="litres?|liters?|L"
U_OZ="ounces?|oz"
U_G="grams?|grammes?|g"
U_IN="inches|inch|in"
U_CM="centimetres?|centimeters?|cm"
U_F="°F|degrees Fahrenheit|degrees F|fahrenheit"
U_C="°C|degrees Celsius|degrees C|celsius|centigrade"

# Master pattern: any recognized unit string (used in regex)
U_ANY="${U_KG}|${U_LB}|${U_MI}|${U_KM}|${U_FT}|${U_M}|${U_GAL}|${U_L}|${U_OZ}|${U_G}|${U_IN}|${U_CM}|${U_F}|${U_C}"

# --- Counters ---

FILES_SCANNED=0
PAIRS_CHECKED=0
MISMATCHES=0
THRESHOLD_HITS=0
FILES_WITH_ERRORS=0

# --- Functions ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <FILE|DIRECTORY>...

Scan text files for unit-conversion claims and validate them against
deterministic constants. Catches imprecision and threshold-crossing
errors common in LLM-generated logistics, compliance, and shipping docs.

Options:
  --tolerance PCT      Relative tolerance percentage (default: 0.5)
  --strict             Tighten tolerance to 0.05% (compliance-grade)
  --threshold U:V      Flag conversions that cross V in unit U.
                       Repeatable. Example: --threshold lb:1000
  --no-recursive       Don't recurse into subdirectories
  --summary            Print summary statistics only
  --ci, --quiet        CI mode (suppress detail, non-zero exit on findings)
  -h, --help           Show this help message

Environment:
  UNIT_CHECK_SKIP=1    Skip all checks

Supported units:
  Mass       kg, lb (and synonyms: kilograms, pounds, lbs)
  Length     mi, km, ft, m, in, cm
  Volume     gal, L
  Mass-fine  oz, g
  Temp       °F, °C (degree symbol or "fahrenheit"/"celsius")

Patterns detected:
  "454 kg = 1000.9 lb"
  "454 kg (≈ 1000.9 lb)"
  "454 kilograms equals 1001 pounds"

Exit codes:
  0  No violations found (or UNIT_CHECK_SKIP=1)
  1  One or more inaccuracies or threshold crossings found
  2  Usage error
EOF
}

# Normalize a matched unit string to its canonical short form.
normalize_unit() {
  local u
  u=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$u" in
    kg|kgs|kilogram|kilograms)              echo "kg" ;;
    lb|lbs|pound|pounds)                    echo "lb" ;;
    mi|mile|miles)                          echo "mi" ;;
    km|kilometer|kilometers|kilometre|kilometres) echo "km" ;;
    ft|foot|feet)                           echo "ft" ;;
    m|meter|meters|metre|metres)            echo "m" ;;
    gal|gallon|gallons)                     echo "gal" ;;
    l|liter|liters|litre|litres)            echo "L" ;;
    oz|ounce|ounces)                        echo "oz" ;;
    g|gram|grams|gramme|grammes)            echo "g" ;;
    in|inch|inches)                         echo "in" ;;
    cm|centimeter|centimeters|centimetre|centimetres) echo "cm" ;;
    "°f"|fahrenheit|"degrees fahrenheit"|"degrees f") echo "F" ;;
    "°c"|celsius|centigrade|"degrees celsius"|"degrees c") echo "C" ;;
    *) echo "" ;;
  esac
}

# Compute deterministic conversion. Echoes float string or empty on failure.
convert_unit() {
  local val="$1" from="$2" to="$3"
  awk -v v="$val" -v f="$from" -v t="$to" '
    BEGIN {
      result = ""
      if      (f=="kg"  && t=="lb")  result = v * 2.20462262
      else if (f=="lb"  && t=="kg")  result = v / 2.20462262
      else if (f=="mi"  && t=="km")  result = v * 1.609344
      else if (f=="km"  && t=="mi")  result = v / 1.609344
      else if (f=="ft"  && t=="m")   result = v * 0.3048
      else if (f=="m"   && t=="ft")  result = v / 0.3048
      else if (f=="in"  && t=="cm")  result = v * 2.54
      else if (f=="cm"  && t=="in")  result = v / 2.54
      else if (f=="gal" && t=="L")   result = v * 3.785411784
      else if (f=="L"   && t=="gal") result = v / 3.785411784
      else if (f=="oz"  && t=="g")   result = v * 28.3495231
      else if (f=="g"   && t=="oz")  result = v / 28.3495231
      else if (f=="F"   && t=="C")   result = (v - 32) * 5/9
      else if (f=="C"   && t=="F")   result = v * 9/5 + 32
      else { exit 0 }
      printf "%.4f", result
    }
  '
}

# Check whether two values fall on opposite sides of a threshold.
# Returns 0 (true) if they cross, 1 otherwise.
crosses_threshold() {
  local claimed="$1" actual="$2" threshold="$3"
  awk -v c="$claimed" -v a="$actual" -v t="$threshold" '
    BEGIN {
      cs = (c < t) ? -1 : ((c > t) ? 1 : 0)
      as = (a < t) ? -1 : ((a > t) ? 1 : 0)
      if (cs != as && cs != 0 && as != 0) exit 0
      exit 1
    }
  '
}

# Validate a claimed conversion. Echoes "INACCURATE|<details>" or
# "THRESHOLD|<details>" on a violation; returns 0 on violation, 1 on pass.
check_pair() {
  local src_val="$1" src_unit="$2" claimed_val="$3" claimed_unit="$4"
  local actual diff_pct violation_type=""

  actual=$(convert_unit "$src_val" "$src_unit" "$claimed_unit")
  [[ -z "$actual" ]] && return 1

  diff_pct=$(awk -v a="$actual" -v c="$claimed_val" '
    BEGIN {
      if (a == 0) { print "0.0000"; exit }
      d = (c - a) / a * 100
      if (d < 0) d = -d
      printf "%.4f", d
    }
  ')

  # Inaccuracy check (relative tolerance)
  if (( $(awk -v d="$diff_pct" -v t="$TOLERANCE_PCT" 'BEGIN { print (d > t) }') )); then
    violation_type="INACCURATE"
  fi

  # Threshold check
  for entry in "${THRESHOLDS[@]:-}"; do
    [[ -z "$entry" ]] && continue
    local t_unit="${entry%%:*}" t_val="${entry##*:}"
    if [[ "$t_unit" == "$claimed_unit" ]]; then
      if crosses_threshold "$claimed_val" "$actual" "$t_val"; then
        if [[ -n "$violation_type" ]]; then
          violation_type="INACC+THRESH"
        else
          violation_type="THRESHOLD"
        fi
      fi
    fi
  done

  if [[ -n "$violation_type" ]]; then
    echo "${violation_type}|${src_val} ${src_unit}|${claimed_val} ${claimed_unit}|${actual} ${claimed_unit}|${diff_pct}"
    return 0
  fi
  return 1
}

report_hit() {
  local file="$1" lnum="$2" line="$3" result="$4"
  local vtype source claimed actual diff_pct
  IFS='|' read -r vtype source claimed actual diff_pct <<< "$result"

  case "$vtype" in
    INACCURATE)    MISMATCHES=$((MISMATCHES + 1)) ;;
    THRESHOLD)     THRESHOLD_HITS=$((THRESHOLD_HITS + 1)) ;;
    INACC+THRESH)  MISMATCHES=$((MISMATCHES + 1)); THRESHOLD_HITS=$((THRESHOLD_HITS + 1)) ;;
  esac

  [[ "$SUMMARY_ONLY" -eq 1 ]] && return 0

  printf "  %s:%d  [%s]\n" "$file" "$lnum" "$vtype"
  printf "    Source:  %s\n" "$source"
  printf "    Claimed: %s\n" "$claimed"
  printf "    Actual:  %s  (delta: %s%%)\n" "$actual" "$diff_pct"

  local trimmed="${line#"${line%%[![:space:]]*}"}"
  [[ ${#trimmed} -gt 120 ]] && trimmed="${trimmed:0:117}..."
  printf "    > %s\n\n" "$trimmed"
}

# --- Pattern functions ---
# Each tries one regex against a line. Returns 0 on a violation found.

# Pattern 1: NUM UNIT_A [marker] NUM UNIT_B
#   "454 kg = 998.8 lb"  "454 kilograms equals 1001 pounds"
try_equals() {
  local file="$1" lnum="$2" line="$3"
  local marker="(=|≈|≃|equals|equal to|equivalent to|approximately|approx\.?|or|is)"
  local p="([0-9]+\.?[0-9]*)[[:space:]]*(${U_ANY})[[:space:]]+${marker}[[:space:]]+([0-9]+\.?[0-9]*)[[:space:]]*(${U_ANY})"

  [[ "$line" =~ $p ]] || return 1

  # Capture groups: 1=src_val, 2=src_unit, 3=marker, 4=claimed_val, 5=claimed_unit
  local src_val="${BASH_REMATCH[1]}" src_unit_raw="${BASH_REMATCH[2]}"
  local claimed_val="${BASH_REMATCH[4]}" claimed_unit_raw="${BASH_REMATCH[5]}"
  local src_unit claimed_unit result

  src_unit=$(normalize_unit "$src_unit_raw")
  claimed_unit=$(normalize_unit "$claimed_unit_raw")
  [[ -z "$src_unit" || -z "$claimed_unit" || "$src_unit" == "$claimed_unit" ]] && return 1

  PAIRS_CHECKED=$((PAIRS_CHECKED + 1))

  if result=$(check_pair "$src_val" "$src_unit" "$claimed_val" "$claimed_unit"); then
    report_hit "$file" "$lnum" "$line" "$result"
    return 0
  fi
  return 1
}

# Pattern 2: NUM UNIT_A (NUM UNIT_B) — paren style
#   "454 kg (998.8 lb)"  "100 km (≈ 62.1 mi)"
try_paren() {
  local file="$1" lnum="$2" line="$3"
  local p="([0-9]+\.?[0-9]*)[[:space:]]*(${U_ANY})[[:space:]]*\([[:space:]]*[≈~]?[[:space:]]*([0-9]+\.?[0-9]*)[[:space:]]*(${U_ANY})[[:space:]]*\)"

  [[ "$line" =~ $p ]] || return 1

  local src_val="${BASH_REMATCH[1]}" src_unit_raw="${BASH_REMATCH[2]}"
  local claimed_val="${BASH_REMATCH[3]}" claimed_unit_raw="${BASH_REMATCH[4]}"
  local src_unit claimed_unit result

  src_unit=$(normalize_unit "$src_unit_raw")
  claimed_unit=$(normalize_unit "$claimed_unit_raw")
  [[ -z "$src_unit" || -z "$claimed_unit" || "$src_unit" == "$claimed_unit" ]] && return 1

  PAIRS_CHECKED=$((PAIRS_CHECKED + 1))

  if result=$(check_pair "$src_val" "$src_unit" "$claimed_val" "$claimed_unit"); then
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

    # Quick filter: line must contain a digit and a candidate unit token.
    [[ "$line" =~ [0-9] ]] || continue

    if try_equals "$file" "$line_num" "$line"; then
      file_hits=$((file_hits + 1))
    elif try_paren "$file" "$line_num" "$line"; then
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
    --tolerance)    TOLERANCE_PCT="$2"; shift 2 ;;
    --strict)       STRICT=1; TOLERANCE_PCT="0.05"; shift ;;
    --threshold)    THRESHOLDS+=("$2"); shift 2 ;;
    --no-recursive) RECURSIVE=0; shift ;;
    --summary)      SUMMARY_ONLY=1; shift ;;
    --ci|--quiet)   QUIET=1; SUMMARY_ONLY=1; shift ;;
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

if [[ "${UNIT_CHECK_SKIP:-0}" == "1" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "unit-check: UNIT_CHECK_SKIP=1, skipping checks."
  exit 0
fi

# --- Scan targets ---

if [[ "$QUIET" -eq 0 ]] && [[ "$SUMMARY_ONLY" -eq 0 ]]; then
  echo "=============================================="
  echo " UNIT CHECK: Validating conversions"
  echo "=============================================="
  echo "  Tolerance: ${TOLERANCE_PCT}% (relative)"
  if [[ ${#THRESHOLDS[@]} -gt 0 ]]; then
    echo "  Thresholds: ${THRESHOLDS[*]}"
  fi
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
  echo "  Files scanned:           $FILES_SCANNED"
  echo "  Conversion pairs found:  $PAIRS_CHECKED"
  echo "  Inaccuracies:            $MISMATCHES"
  echo "  Threshold crossings:     $THRESHOLD_HITS"
  echo "  Files with violations:   $FILES_WITH_ERRORS"
  echo ""

  if [[ "$MISMATCHES" -eq 0 ]] && [[ "$THRESHOLD_HITS" -eq 0 ]]; then
    echo "  All conversions within tolerance."
    echo ""
  elif [[ "$SUMMARY_ONLY" -eq 0 ]]; then
    echo "  Conversions were validated against full-precision constants."
    echo "  Inaccuracies exceeded the configured relative tolerance."
    if [[ ${#THRESHOLDS[@]} -gt 0 ]]; then
      echo "  Threshold crossings indicate the claimed value falls on the"
      echo "  opposite side of a configured threshold from the deterministic"
      echo "  value, which routes downstream decisions to the wrong tier."
    fi
    echo ""
  fi
fi

if [[ "$MISMATCHES" -gt 0 ]] || [[ "$THRESHOLD_HITS" -gt 0 ]]; then
  exit 1
fi
exit 0

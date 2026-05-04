#!/usr/bin/env bash
set -euo pipefail

# schema-shadow: Audit LLM-emitted JSON payloads for the failure modes
# that JSON Schema validation cannot catch.
#
# JSON Schema validates that fields exist with the right types. It does
# not validate that the values are correct, that array lengths match an
# expected pattern, or that the model didn't silently drop a populated
# field one call to the next. This script runs four checks against a
# directory of payloads, comparing each against a baseline payload of
# the same schema.
#
# Checks:
#   1. Dropped fields:    paths populated in the baseline that are
#                         missing or null in the payload.
#   2. Type coercion:     string-shaped numbers, ISO-date strings parsed
#                         as plain text, booleans-as-strings.
#   3. Array drift:       payload array lengths diverging from baseline
#                         beyond a configurable tolerance.
#   4. Field-order drift: top-level key order differs from the baseline,
#                         a soft signal of internal-generation drift.
#
# Scan a directory against a baseline:
#   ./schema-shadow.sh --baseline baseline.json ./payloads
#
# Scan a directory against a directory of baselines (matched by basename):
#   ./schema-shadow.sh --baseline-dir ./baselines ./payloads
#
# CI mode (silent on success, non-zero exit on findings):
#   ./schema-shadow.sh --ci --baseline baseline.json ./production-batch
#
# From Bashmatica! #13.

# --- Configuration ---

QUIET=0
SUMMARY_ONLY=0
RECURSIVE=1
ARRAY_TOLERANCE_PCT="10"     # default: array length drift tolerance, percent
BASELINE=""
BASELINE_DIR=""
SKIP_TYPE_CHECK=0
SKIP_ORDER_CHECK=0

# --- Counters ---

FILES_SCANNED=0
DROPPED_FIELDS=0
TYPE_COERCIONS=0
ARRAY_DRIFTS=0
ORDER_DRIFTS=0
FILES_WITH_FINDINGS=0

# --- Functions ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] <FILE|DIRECTORY>...

Audit LLM-emitted JSON payloads for failure modes JSON Schema cannot catch.

Required (one of):
  --baseline FILE       Single baseline payload to compare against.
  --baseline-dir DIR    Directory of baseline payloads, matched by basename.

Options:
  --array-tolerance PCT Array length drift tolerance (default: 10%).
  --no-type-check       Skip the type-coercion check.
  --no-order-check      Skip the field-order-drift check.
  --no-recursive        Don't recurse into subdirectories.
  --summary             Print summary statistics only.
  --ci, --quiet         Suppress detail output, non-zero exit on findings.
  -h, --help            Show this help message.

Environment:
  SCHEMA_SHADOW_SKIP=1  Skip all checks (exit 0).

Output format (one finding per line):
  <type>|<file>|<detail>

Where <type> is one of: dropped, type-coerced, array-drift, order-drift.

Requires: jq.
EOF
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed." >&2
    echo "Install: brew install jq  (macOS) | apt install jq  (Debian/Ubuntu)" >&2
    exit 2
  fi
}

# Print a finding (respects --ci/quiet).
emit() {
  if [[ "$QUIET" -eq 0 ]] && [[ "$SUMMARY_ONLY" -eq 0 ]]; then
    echo "$1"
  fi
}

# Compare a payload's populated leaf paths against a baseline. Anything
# the baseline populated and the payload omitted (or null-emitted) is
# flagged as dropped.
check_dropped_fields() {
  local baseline="$1" payload="$2"
  local baseline_keys payload_keys missing count=0

  baseline_keys=$(jq -r '[paths(scalars and . != null)] | map(map(tostring) | join(".")) | .[]' "$baseline" 2>/dev/null | sort -u || true)
  payload_keys=$(jq -r '[paths(scalars and . != null)] | map(map(tostring) | join(".")) | .[]' "$payload" 2>/dev/null | sort -u || true)

  if [[ -z "$baseline_keys" ]]; then
    return 0
  fi

  missing=$(comm -23 <(echo "$baseline_keys") <(echo "$payload_keys") || true)

  if [[ -n "$missing" ]]; then
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      emit "dropped|${payload}|${key}"
      count=$((count + 1))
    done <<< "$missing"
  fi

  DROPPED_FIELDS=$((DROPPED_FIELDS + count))
  return 0
}

# Detect string-shaped values that look like numbers, ISO dates, or
# booleans. These commonly arise when the model "satisfies" a string
# field with content that should have been a richer type.
check_type_coercion() {
  local payload="$1"
  local findings count=0

  # Bind document to $doc and capture each path as $p before piping into
  # $doc — otherwise the parenthesized sub-pipeline rebinds . to $doc
  # and getpath loses the path argument.
  findings=$(jq -r '
    . as $doc
    | [paths(strings)] as $paths
    | $paths[]
    | . as $p
    | {path: ($p | map(tostring) | join(".")), value: ($doc | getpath($p))}
    | select(.value | test("^-?[0-9]+(\\.[0-9]+)?$") or test("^[0-9]{4}-[0-9]{2}-[0-9]{2}") or test("^(true|false)$"; "i"))
    | "\(.path)|\(.value)"
  ' "$payload" 2>/dev/null || true)

  if [[ -n "$findings" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      emit "type-coerced|${payload}|${line}"
      count=$((count + 1))
    done <<< "$findings"
  fi

  TYPE_COERCIONS=$((TYPE_COERCIONS + count))
  return 0
}

# Compare array lengths between baseline and payload at the same paths.
# Flag any path whose length deviates by more than ARRAY_TOLERANCE_PCT.
check_array_drift() {
  local baseline="$1" payload="$2"
  local count=0

  # All array paths in baseline.
  local array_paths
  array_paths=$(jq -r '[paths(arrays)] | map(map(tostring) | join(".")) | .[]' "$baseline" 2>/dev/null || true)

  if [[ -z "$array_paths" ]]; then
    return 0
  fi

  while IFS= read -r path; do
    [[ -z "$path" ]] && continue

    local jq_path
    # Convert dot-path "a.b.0.c" to jq path "[\"a\",\"b\",0,\"c\"]"
    jq_path=$(printf '%s' "$path" | awk -F. '{
      printf "["
      for (i=1; i<=NF; i++) {
        if ($i ~ /^[0-9]+$/) { printf "%s", $i } else { printf "\"%s\"", $i }
        if (i<NF) printf ","
      }
      printf "]"
    }')

    local b_len p_len
    b_len=$(jq -r "getpath(${jq_path}) | if type == \"array\" then length else 0 end" "$baseline" 2>/dev/null || echo 0)
    p_len=$(jq -r "getpath(${jq_path}) | if type == \"array\" then length else -1 end" "$payload" 2>/dev/null || echo -1)

    [[ "$p_len" == "-1" ]] && continue
    [[ "$b_len" -eq 0 ]] && continue

    # Compute absolute percent diff.
    local diff_pct
    diff_pct=$(awk -v a="$b_len" -v b="$p_len" 'BEGIN { d = (a - b); if (d < 0) d = -d; printf "%.2f", (d / a) * 100 }')

    # Compare to tolerance.
    local over
    over=$(awk -v d="$diff_pct" -v t="$ARRAY_TOLERANCE_PCT" 'BEGIN { print (d > t) ? 1 : 0 }')

    if [[ "$over" -eq 1 ]]; then
      emit "array-drift|${payload}|${path} baseline=${b_len} payload=${p_len} diff=${diff_pct}%"
      count=$((count + 1))
    fi
  done <<< "$array_paths"

  ARRAY_DRIFTS=$((ARRAY_DRIFTS + count))
  return 0
}

# Compare top-level key order between baseline and payload. A soft signal,
# not an error per se, but useful in tracking down generation drift.
check_order_drift() {
  local baseline="$1" payload="$2"
  local b_order p_order

  b_order=$(jq -r 'keys_unsorted | join(",")' "$baseline" 2>/dev/null || true)
  p_order=$(jq -r 'keys_unsorted | join(",")' "$payload" 2>/dev/null || true)

  if [[ -n "$b_order" ]] && [[ -n "$p_order" ]] && [[ "$b_order" != "$p_order" ]]; then
    emit "order-drift|${payload}|baseline=[${b_order}] payload=[${p_order}]"
    ORDER_DRIFTS=$((ORDER_DRIFTS + 1))
  fi
  return 0
}

# Resolve which baseline applies to a payload. With --baseline, always
# the same file. With --baseline-dir, match by basename.
resolve_baseline() {
  local payload="$1"
  if [[ -n "$BASELINE" ]]; then
    echo "$BASELINE"
    return 0
  fi
  if [[ -n "$BASELINE_DIR" ]]; then
    local base
    base=$(basename "$payload")
    if [[ -f "${BASELINE_DIR%/}/${base}" ]]; then
      echo "${BASELINE_DIR%/}/${base}"
      return 0
    fi
  fi
  return 1
}

scan_file() {
  local payload="$1"
  local baseline
  local before_drop=$DROPPED_FIELDS
  local before_type=$TYPE_COERCIONS
  local before_array=$ARRAY_DRIFTS
  local before_order=$ORDER_DRIFTS

  if ! baseline=$(resolve_baseline "$payload"); then
    [[ "$QUIET" -eq 0 ]] && echo "skipping (no baseline): $payload" >&2
    return 0
  fi

  if ! jq empty "$payload" >/dev/null 2>&1; then
    emit "parse-error|${payload}|invalid JSON"
    FILES_WITH_FINDINGS=$((FILES_WITH_FINDINGS + 1))
    return 0
  fi

  FILES_SCANNED=$((FILES_SCANNED + 1))

  check_dropped_fields "$baseline" "$payload"
  [[ "$SKIP_TYPE_CHECK" -eq 0 ]] && check_type_coercion "$payload"
  check_array_drift "$baseline" "$payload"
  [[ "$SKIP_ORDER_CHECK" -eq 0 ]] && check_order_drift "$baseline" "$payload"

  local added=$(( (DROPPED_FIELDS - before_drop) + (TYPE_COERCIONS - before_type) + (ARRAY_DRIFTS - before_array) + (ORDER_DRIFTS - before_order) ))
  if [[ $added -gt 0 ]]; then
    FILES_WITH_FINDINGS=$((FILES_WITH_FINDINGS + 1))
  fi
}

find_payloads() {
  local target="$1"
  if [[ -f "$target" ]]; then
    echo "$target"
    return 0
  fi
  if [[ "$RECURSIVE" -eq 1 ]]; then
    find "$target" \
      \( -name .git -o -name node_modules -o -name __pycache__ \
         -o -name vendor -o -name .venv -o -name venv \
         -o -name dist -o -name build -o -name .next \) -prune \
      -o -type f -name "*.json" -print 2>/dev/null | sort
  else
    find "$target" -maxdepth 1 -type f -name "*.json" 2>/dev/null | sort
  fi
}

# --- Parse arguments ---

TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline)         BASELINE="$2"; shift 2 ;;
    --baseline-dir)     BASELINE_DIR="$2"; shift 2 ;;
    --array-tolerance)  ARRAY_TOLERANCE_PCT="$2"; shift 2 ;;
    --no-type-check)    SKIP_TYPE_CHECK=1; shift ;;
    --no-order-check)   SKIP_ORDER_CHECK=1; shift ;;
    --no-recursive)     RECURSIVE=0; shift ;;
    --summary)          SUMMARY_ONLY=1; shift ;;
    --ci|--quiet)       QUIET=1; SUMMARY_ONLY=1; shift ;;
    -h|--help)          usage; exit 0 ;;
    -*)                 echo "Unknown option: $1" >&2; usage; exit 2 ;;
    *)                  TARGETS+=("$1"); shift ;;
  esac
done

if [[ "${SCHEMA_SHADOW_SKIP:-0}" == "1" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "schema-shadow: SCHEMA_SHADOW_SKIP=1, skipping checks."
  exit 0
fi

require_jq

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "Error: No files or directories specified." >&2
  echo "" >&2
  usage
  exit 2
fi

if [[ -z "$BASELINE" ]] && [[ -z "$BASELINE_DIR" ]]; then
  echo "Error: --baseline or --baseline-dir required." >&2
  echo "" >&2
  usage
  exit 2
fi

if [[ -n "$BASELINE" ]] && [[ ! -f "$BASELINE" ]]; then
  echo "Error: baseline file not found: $BASELINE" >&2
  exit 2
fi

if [[ -n "$BASELINE_DIR" ]] && [[ ! -d "$BASELINE_DIR" ]]; then
  echo "Error: baseline directory not found: $BASELINE_DIR" >&2
  exit 2
fi

# --- Header ---

if [[ "$QUIET" -eq 0 ]] && [[ "$SUMMARY_ONLY" -eq 0 ]]; then
  echo "=============================================="
  echo " SCHEMA SHADOW: Auditing LLM JSON payloads"
  echo "=============================================="
  if [[ -n "$BASELINE" ]]; then
    echo "  Baseline: $BASELINE"
  else
    echo "  Baseline dir: $BASELINE_DIR"
  fi
  echo "  Array tolerance: ${ARRAY_TOLERANCE_PCT}%"
  echo ""
fi

# --- Scan targets ---

for target in "${TARGETS[@]}"; do
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    scan_file "$f"
  done < <(find_payloads "$target")
done

# --- Summary ---

TOTAL_FINDINGS=$(( DROPPED_FIELDS + TYPE_COERCIONS + ARRAY_DRIFTS + ORDER_DRIFTS ))

if [[ "$QUIET" -eq 0 ]]; then
  echo ""
  echo "=============================================="
  echo " SUMMARY"
  echo "=============================================="
  echo "  Files scanned:        $FILES_SCANNED"
  echo "  Files with findings:  $FILES_WITH_FINDINGS"
  echo "  Dropped fields:       $DROPPED_FIELDS"
  echo "  Type coercions:       $TYPE_COERCIONS"
  echo "  Array drifts:         $ARRAY_DRIFTS"
  echo "  Order drifts:         $ORDER_DRIFTS"
  echo "  Total findings:       $TOTAL_FINDINGS"
  echo ""
fi

# Exit code: 0 if clean, 1 if any findings (CI-friendly).
[[ $TOTAL_FINDINGS -eq 0 ]]

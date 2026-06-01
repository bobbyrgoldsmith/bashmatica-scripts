#!/usr/bin/env bash
#
# env-drift.sh — Catch environment drift before your app boots into it.
#
# Compares a reference manifest of expected environment keys (a .env.example,
# or a plain list of KEY names) against the actual environment — either a .env
# file or the live process environment — and reports three kinds of drift:
#
#   MISSING — key is in the reference but absent from the actual env
#   EMPTY   — key is present in the actual env but its value is blank
#   EXTRA   — key is in the actual env but not in the reference
#
# MISSING and EMPTY are failures (an app that boots with a blank API key fails
# silently, often as an empty collection or a 401 three layers down). EXTRA is
# a warning — usually harmless, occasionally a leftover secret or a typo'd key.
#
# Usage:
#   ./env-drift.sh <reference> <actual.env>
#   ./env-drift.sh --from-env <reference>     # compare against the live shell env
#   ./env-drift.sh --strict <reference> <actual.env>   # EXTRA also fails
#   ./env-drift.sh --example
#
# Exit codes:
#   0 — no drift (or EXTRA-only in non-strict mode)
#   1 — at least one MISSING or EMPTY key (or any drift in --strict mode)
#   2 — usage / input error
#
# Requires: bash 3.2+, GNU or BSD coreutils (comm, sort, grep, sed)

set -euo pipefail

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//' | sed '1d'
  exit "${1:-2}"
}

# ----------------------------------------------------------------------
# Parse args
# ----------------------------------------------------------------------
STRICT=0
FROM_ENV=0
REF=""
ACTUAL=""
POSITIONAL=()

for arg in "$@"; do
  case "$arg" in
    --strict)   STRICT=1 ;;
    --from-env) FROM_ENV=1 ;;
    --example)
      REF="$(dirname "$0")/examples/.env.example"
      ACTUAL="$(dirname "$0")/examples/.env"
      ;;
    -h|--help)  usage 0 ;;
    -*)         echo "Unknown option: $arg" >&2; usage 2 ;;
    *)          POSITIONAL+=("$arg") ;;
  esac
done

# Positional args fill whatever --example / --from-env did not set.
if [[ -z "$REF" && ${#POSITIONAL[@]} -ge 1 ]]; then
  REF="${POSITIONAL[0]}"
  if [[ "$FROM_ENV" -eq 0 && ${#POSITIONAL[@]} -ge 2 ]]; then
    ACTUAL="${POSITIONAL[1]}"
  fi
fi

if [[ -z "$REF" ]]; then
  echo "Error: no reference manifest given" >&2
  usage 2
fi
if [[ ! -f "$REF" ]]; then
  echo "Error: reference not found: $REF" >&2
  exit 2
fi
if [[ "$FROM_ENV" -eq 0 ]]; then
  if [[ -z "$ACTUAL" ]]; then
    echo "Error: no actual .env file given (or pass --from-env)" >&2
    usage 2
  fi
  if [[ ! -f "$ACTUAL" ]]; then
    echo "Error: actual env file not found: $ACTUAL" >&2
    exit 2
  fi
fi

# ----------------------------------------------------------------------
# Key extraction
#
# A "key line" is an optional `export`, then a KEY, then either `=` or EOL.
# Comment (#) and blank lines never match. Values are ignored for key lists.
# ----------------------------------------------------------------------
extract_keys() {
  grep -E '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*([[:space:]]*=|[[:space:]]*$)' "$1" \
    | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/[[:space:]]*=.*$//; s/[[:space:]]*$//' \
    | sort -u
}

# Value of a key from a .env file: last assignment wins; strip quotes,
# surrounding whitespace, and a trailing inline comment.
val_in_file() {
  local key="$1" file="$2" line
  line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?$key[[:space:]]*=" "$file" | tail -n1 || true)
  line="${line#*=}"
  # trim leading/trailing whitespace
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  # strip a single layer of matching quotes
  if [[ "$line" == \"*\" || "$line" == \'*\' ]]; then
    line="${line:1:${#line}-2}"
  fi
  printf '%s' "$line"
}

REF_KEYS=$(extract_keys "$REF")

if [[ "$FROM_ENV" -eq 1 ]]; then
  ACTUAL_KEYS=$(printenv | sed -E 's/=.*$//' | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u)
else
  ACTUAL_KEYS=$(extract_keys "$ACTUAL")
fi

# ----------------------------------------------------------------------
# Set differences via comm (operands must be sorted; they are)
# ----------------------------------------------------------------------
MISSING=$(comm -23 <(printf '%s\n' "$REF_KEYS") <(printf '%s\n' "$ACTUAL_KEYS"))
EXTRA=$(comm -13 <(printf '%s\n' "$REF_KEYS") <(printf '%s\n' "$ACTUAL_KEYS"))
SHARED=$(comm -12 <(printf '%s\n' "$REF_KEYS") <(printf '%s\n' "$ACTUAL_KEYS"))

FAIL=0
WARN=0

for k in $MISSING; do
  [[ -z "$k" ]] && continue
  echo "MISSING  $k — declared in reference, absent from actual env"
  FAIL=$((FAIL + 1))
done

for k in $SHARED; do
  [[ -z "$k" ]] && continue
  if [[ "$FROM_ENV" -eq 1 ]]; then
    v="$(printenv "$k" || true)"
  else
    v="$(val_in_file "$k" "$ACTUAL")"
  fi
  if [[ -z "$v" ]]; then
    echo "EMPTY    $k — present but value is blank"
    FAIL=$((FAIL + 1))
  else
    echo "OK       $k"
  fi
done

for k in $EXTRA; do
  [[ -z "$k" ]] && continue
  echo "EXTRA    $k — in actual env, not in reference"
  WARN=$((WARN + 1))
done

# ----------------------------------------------------------------------
# Summary + exit
# ----------------------------------------------------------------------
echo
echo "Summary: $FAIL drift failure(s), $WARN warning(s)"

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
if [[ "$STRICT" -eq 1 && "$WARN" -gt 0 ]]; then
  exit 1
fi
exit 0

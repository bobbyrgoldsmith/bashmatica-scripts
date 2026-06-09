#!/usr/bin/env bash
#
# intent-lint.sh — Validate a test-intent manifest before a maintenance agent
# ever reads it, so the agent is grounded instead of guessing.
#
# A maintenance agent looking at a broken test has to answer one question before
# it can fix anything: what was this test supposed to verify? Without a manifest
# it guesses, and a guess that compiles is the most expensive kind of wrong. A
# testscout.config.yaml (or any equivalent test-intent manifest) answers that
# question deterministically: every test declares its intent, its criticality,
# and the ranked fallback selectors a healer can reach for. But a manifest is
# only grounding if it is complete and if it matches reality on disk. A test
# with no declared intent grounds nothing. A config entry pointing at a file
# that was deleted grounds nothing. A test file on disk with no entry is a blind
# spot the agent will improvise into.
#
# intent-lint refuses an incomplete or out-of-sync manifest before the agent
# trusts it. Five checks:
#
#   INTENT       — every test declares an intent (what it verifies). A test with
#                  no intent gives a maintenance agent nothing to preserve. FAIL.
#   CRITICALITY  — every test declares a criticality (critical/high/medium/low).
#                  Without it the Planner can't tell a deploy-gating test from a
#                  nice-to-have, and prioritizes blind. FAIL.
#   FALLBACKS    — every test that names pages_involved touches at least one
#                  element with a ranked fallback chain. A test with zero
#                  fallbacks anywhere forces the healer to invent a selector
#                  from scratch, the lowest-confidence fix there is. WARN
#                  (FAIL under --strict).
#   ORPHAN-CFG   — every test entry's file: exists on disk. A config entry whose
#                  file was deleted or moved is stale grounding. FAIL.
#   ORPHAN-DISK  — every test file under test_dir has a config entry. A test on
#                  disk with no entry is a test the agent will maintain by guess.
#                  WARN (FAIL under --strict).
#
# A manifest that clears all five is grounding a maintenance agent can trust.
# One that doesn't is a guess wearing a config file's clothes.
#
# Usage:
#   ./intent-lint.sh --config <manifest.yaml>
#   ./intent-lint.sh --config ./testscout.config.yaml
#   ./intent-lint.sh --config ./testscout.config.yaml --strict   # WARNs also fail
#   ./intent-lint.sh --example
#
# Options:
#   --config <file>   The test-intent manifest to validate (required, unless
#                     --example). Expects testscout.config.yaml shape: a top-level
#                     `tests:` mapping, optional `pages:` mapping, and
#                     `project.test_dir`.
#   --strict          FALLBACKS and ORPHAN-DISK warnings also refuse the manifest.
#   --ext <glob>      Test-file extension(s) for the on-disk scan, comma-separated.
#                     Default: spec.ts,spec.js,test.ts,test.js,cy.js,_test.py
#   --example         Run against the bundled sample manifest (a deleted-file
#                     entry, a test with no intent, a test with no criticality,
#                     a page with no fallbacks, and an un-configured test on disk).
#
# Exit codes:
#   0 — CLEAN. The manifest grounds a maintenance agent. (Possibly with warnings.)
#   1 — NOT CLEAN. At least one check refused it.
#   2 — usage / input error.
#
# Requires: bash 3.2+, awk, grep, find. Fact extraction is a pure-awk parser for
# the regular testscout.config.yaml shape, so there is no hard YAML dependency.
# If `yq` happens to be installed it is used only to reject a syntactically
# broken manifest up front; nothing else changes.

set -uo pipefail

usage() {
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
  exit "${1:-2}"
}

# ----------------------------------------------------------------------
# Parse args
# ----------------------------------------------------------------------
CONFIG=""
STRICT=0
EXTS="spec.ts,spec.js,test.ts,test.js,cy.js,_test.py"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG="${2:-}"; shift 2 ;;
    --strict)  STRICT=1; shift ;;
    --ext)     EXTS="${2:-}"; shift 2 ;;
    --example)
      CONFIG="$SELF_DIR/examples/testscout.config.yaml"
      shift ;;
    -h|--help) usage 0 ;;
    *)         echo "Unknown option: $1" >&2; usage 2 ;;
  esac
done

if [[ -z "$CONFIG" ]]; then
  echo "Error: no --config manifest given" >&2
  usage 2
fi
if [[ ! -f "$CONFIG" ]]; then
  echo "Error: config not found: $CONFIG" >&2
  exit 2
fi

CONFIG_DIR="$(cd "$(dirname "$CONFIG")" && pwd)"

# ----------------------------------------------------------------------
# Parse the manifest into flat, greppable records.
#
# We emit one record per fact we care about, on stdout from the parser:
#   TEST <name>
#   TESTFILE <name> <path>
#   TESTINTENT <name>
#   TESTCRIT <name>
#   TESTPAGES <name> <page> [<page> ...]
#   PAGEFB <page> <element>        (an element that HAS a fallbacks: list)
#   TESTDIR <path>
#
# A pure-awk parser handles the regular two-and-three-space-indented
# testscout.config.yaml shape. The structure is indentation-regular by spec,
# which is what makes this tractable without a YAML library.
# ----------------------------------------------------------------------
parse_awk() {
  awk '
    function indent(line,   i) { i = 0; while (substr(line, i+1, 1) == " ") i++; return i }
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function strip_q(s) { sub(/^["'\'']/, "", s); sub(/["'\'']$/, "", s); return s }

    BEGIN { section=""; ind_tests=-1; ind_pages=-1; cur_test=""; cur_page=""; cur_elem=""; in_elements=0 }

    # skip blank lines and full-line comments
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }

    {
      ind = indent($0)
      line = trim($0)
      key = line; sub(/:.*/, "", key)
      val = ""
      if (line ~ /:[[:space:]]*[^[:space:]]/) {
        val = line; sub(/^[^:]*:[[:space:]]*/, "", val)
        # strip an unquoted trailing inline comment ( ... value  # note)
        if (val !~ /^["'\'']/) sub(/[[:space:]]+#.*$/, "", val)
        val = strip_q(trim(val))
      }
    }

    # top-level section markers (indent 0)
    ind == 0 {
      section = key
      cur_test=""; cur_page=""; cur_elem=""; in_elements=0
      if (section == "tests") ind_tests = -1
      if (section == "pages") ind_pages = -1
      if (key == "project") section="project"
      next
    }

    # project.test_dir
    section == "project" && key == "test_dir" { print "TESTDIR " val; next }

    # ---------- tests: ----------
    section == "tests" {
      if (ind_tests < 0) ind_tests = ind          # first entry sets the test-name indent
      if (ind == ind_tests) {
        cur_test = key
        print "TEST " cur_test
        next
      }
      if (cur_test != "" && ind > ind_tests) {
        if (key == "file" && val != "")     { print "TESTFILE " cur_test " " val; next }
        if (key == "intent" && val != "")   { print "TESTINTENT " cur_test; next }
        if (key == "criticality" && val != ""){ print "TESTCRIT " cur_test; next }
        if (key == "pages_involved") {
          # inline list form: [a, b]
          if (val ~ /^\[/) {
            gsub(/[][]/, "", val); gsub(/,/, " ", val)
            print "TESTPAGES " cur_test " " trim(val)
          }
          next
        }
        # block list item under pages_involved: "- pagename"
        if (line ~ /^-[[:space:]]*/) {
          item = line; sub(/^-[[:space:]]*/, "", item)
          if (item !~ /^["'\'']/) sub(/[[:space:]]+#.*$/, "", item)
          item = strip_q(trim(item))
          if (item != "") print "TESTPAGES " cur_test " " item
          next
        }
      }
      next
    }

    # ---------- pages: ----------
    section == "pages" {
      if (ind_pages < 0) ind_pages = ind
      if (ind == ind_pages) { cur_page = key; cur_elem=""; in_elements=0; next }
      if (cur_page != "") {
        if (key == "elements") { in_elements = 1; ind_elem = -1; next }
        if (in_elements) {
          if (ind_elem < 0 && key != "" && val == "") { ind_elem = ind }
          if (ind == ind_elem && key != "") { cur_elem = key; next }
          if (cur_elem != "" && key == "fallbacks") {
            print "PAGEFB " cur_page " " cur_elem
            next
          }
        }
      }
      next
    }
  ' "$1"
}

# If yq is present, use it to validate that the file is well-formed YAML before
# we parse it ourselves (a syntactically broken manifest is its own kind of
# refusal). The fact extraction itself is the pure-awk parser either way, so the
# script has no hard dependency on yq.
if command -v yq >/dev/null 2>&1; then
  if ! yq -e '.' "$CONFIG" >/dev/null 2>&1; then
    echo "Error: $CONFIG is not valid YAML (yq could not parse it)" >&2
    exit 2
  fi
fi
RECORDS="$(parse_awk "$CONFIG")"

# Pull the fact sets out of the record stream.
TESTS="$(printf '%s\n' "$RECORDS" | awk '$1=="TEST"{print $2}')"
TESTDIR_REL="$(printf '%s\n' "$RECORDS" | awk '$1=="TESTDIR"{print $2; exit}')"

if [[ -z "$TESTS" ]]; then
  echo "Error: no tests: entries found in $CONFIG (is this a testscout.config.yaml?)" >&2
  exit 2
fi

has_fact() { printf '%s\n' "$RECORDS" | grep -qE "^$1 $2( |\$)"; }

FAIL=0
WARN=0

# ----------------------------------------------------------------------
# Check 1 — INTENT: every test declares an intent.
# ----------------------------------------------------------------------
MISSING_INTENT=""
for t in $TESTS; do
  has_fact "TESTINTENT" "$t" || MISSING_INTENT="$MISSING_INTENT $t"
done
MISSING_INTENT="$(echo "$MISSING_INTENT" | xargs 2>/dev/null || true)"
if [[ -n "$MISSING_INTENT" ]]; then
  echo "INTENT      missing on: $MISSING_INTENT  FAIL"
  FAIL=$((FAIL + 1))
else
  echo "INTENT      every test declares an intent  OK"
fi

# ----------------------------------------------------------------------
# Check 2 — CRITICALITY: every test declares a criticality.
# ----------------------------------------------------------------------
MISSING_CRIT=""
for t in $TESTS; do
  has_fact "TESTCRIT" "$t" || MISSING_CRIT="$MISSING_CRIT $t"
done
MISSING_CRIT="$(echo "$MISSING_CRIT" | xargs 2>/dev/null || true)"
if [[ -n "$MISSING_CRIT" ]]; then
  echo "CRITICALITY missing on: $MISSING_CRIT  FAIL"
  FAIL=$((FAIL + 1))
else
  echo "CRITICALITY every test declares a criticality  OK"
fi

# ----------------------------------------------------------------------
# Check 3 — FALLBACKS: every test that names pages_involved touches at least
# one element that has a ranked fallback chain. A test referencing pages whose
# elements all lack fallbacks leaves a healer nothing to climb down to.
# ----------------------------------------------------------------------
PAGES_WITH_FB="$(printf '%s\n' "$RECORDS" | awk '$1=="PAGEFB"{print $2}' | sort -u)"
NO_FB=""
for t in $TESTS; do
  pages="$(printf '%s\n' "$RECORDS" | awk -v t="$t" '$1=="TESTPAGES" && $2==t {for(i=3;i<=NF;i++)print $i}')"
  [[ -z "$pages" ]] && continue       # a test with no pages_involved isn't selector-bound; skip
  covered=0
  for p in $pages; do
    if printf '%s\n' "$PAGES_WITH_FB" | grep -qx "$p"; then covered=1; break; fi
  done
  [[ "$covered" -eq 0 ]] && NO_FB="$NO_FB $t"
done
NO_FB="$(echo "$NO_FB" | xargs 2>/dev/null || true)"
if [[ -n "$NO_FB" ]]; then
  if [[ "$STRICT" -eq 1 ]]; then
    echo "FALLBACKS   zero fallback selectors reachable from: $NO_FB  FAIL"
    FAIL=$((FAIL + 1))
  else
    echo "FALLBACKS   zero fallback selectors reachable from: $NO_FB  WARN"
    WARN=$((WARN + 1))
  fi
else
  echo "FALLBACKS   every page-bound test reaches a fallback chain  OK"
fi

# ----------------------------------------------------------------------
# Check 4 — ORPHAN-CFG: every test entry's file: exists on disk.
# ----------------------------------------------------------------------
ORPHAN_CFG=""
CONFIGURED_FILES=""
while IFS= read -r rec; do
  [[ -z "$rec" ]] && continue
  name="$(echo "$rec" | awk '{print $2}')"
  path="$(echo "$rec" | cut -d' ' -f3-)"
  abs="$path"
  [[ "$abs" != /* ]] && abs="$CONFIG_DIR/$path"
  CONFIGURED_FILES="$CONFIGURED_FILES$(cd "$(dirname "$abs")" 2>/dev/null && echo "$(pwd)/$(basename "$abs")" || echo "$abs")
"
  [[ -f "$abs" ]] || ORPHAN_CFG="$ORPHAN_CFG $name($path)"
done <<EOF
$(printf '%s\n' "$RECORDS" | awk '$1=="TESTFILE"')
EOF
ORPHAN_CFG="$(echo "$ORPHAN_CFG" | xargs 2>/dev/null || true)"
if [[ -n "$ORPHAN_CFG" ]]; then
  echo "ORPHAN-CFG  config entries point at missing files: $ORPHAN_CFG  FAIL"
  FAIL=$((FAIL + 1))
else
  echo "ORPHAN-CFG  every configured test file exists on disk  OK"
fi

# ----------------------------------------------------------------------
# Check 5 — ORPHAN-DISK: every test file under test_dir has a config entry.
# ----------------------------------------------------------------------
if [[ -n "$TESTDIR_REL" ]]; then
  TDIR="$TESTDIR_REL"
  [[ "$TDIR" != /* ]] && TDIR="$CONFIG_DIR/$TESTDIR_REL"
  if [[ -d "$TDIR" ]]; then
    # build a find expression from the comma-separated extension globs
    FIND_ARGS=()
    OLDIFS="$IFS"; IFS=','
    first=1
    for ext in $EXTS; do
      if [[ "$first" -eq 1 ]]; then FIND_ARGS+=( -name "*.$ext" ); first=0
      else FIND_ARGS+=( -o -name "*.$ext" ); fi
    done
    IFS="$OLDIFS"
    ORPHAN_DISK=""
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      absf="$(cd "$(dirname "$f")" && echo "$(pwd)/$(basename "$f")")"
      if ! printf '%s' "$CONFIGURED_FILES" | grep -qxF "$absf"; then
        ORPHAN_DISK="$ORPHAN_DISK ${f#$CONFIG_DIR/}"
      fi
    done <<EOF
$(find "$TDIR" -type f \( "${FIND_ARGS[@]}" \) 2>/dev/null)
EOF
    ORPHAN_DISK="$(echo "$ORPHAN_DISK" | xargs 2>/dev/null || true)"
    if [[ -n "$ORPHAN_DISK" ]]; then
      if [[ "$STRICT" -eq 1 ]]; then
        echo "ORPHAN-DISK test files on disk with no config entry: $ORPHAN_DISK  FAIL"
        FAIL=$((FAIL + 1))
      else
        echo "ORPHAN-DISK test files on disk with no config entry: $ORPHAN_DISK  WARN"
        WARN=$((WARN + 1))
      fi
    else
      echo "ORPHAN-DISK every test file on disk has a config entry  OK"
    fi
  else
    echo "ORPHAN-DISK test_dir not found ($TESTDIR_REL); skipped  WARN"
    WARN=$((WARN + 1))
  fi
else
  echo "ORPHAN-DISK no project.test_dir declared; skipped  WARN"
  WARN=$((WARN + 1))
fi

# ----------------------------------------------------------------------
# Verdict
# ----------------------------------------------------------------------
echo
if [[ "$FAIL" -gt 0 ]]; then
  echo "Verdict: NOT CLEAN ($FAIL refusal(s), $WARN warning(s))"
  exit 1
fi
if [[ "$WARN" -gt 0 ]]; then
  echo "Verdict: CLEAN WITH WARNINGS ($WARN warning(s) — the manifest grounds the agent, but has gaps)"
  exit 0
fi
echo "Verdict: CLEAN"
exit 0

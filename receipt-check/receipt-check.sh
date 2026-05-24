#!/usr/bin/env bash
# receipt-check — classify procurement claims by receipt tier before deploy.
#
# Reads a JSON file of procurement claims and tiers each by how the supporting
# productivity claim was generated. The point is to refuse irreversible
# decisions (workforce cuts, contract cancellations, infra rip-outs) when the
# only evidence cited is a vendor demo or a vendor case study.
#
# Receipt tiers (weakest -> strongest):
#
#   vendor_demo           — vendor's marketing site, sales deck, demo video
#   vendor_case_study     — vendor-published "success story" with metrics
#   vendor_funded_study   — third-party author, vendor money
#   independent_study     — third-party author, independent funding
#   our_pilot             — production data from our own pilot
#
# Decision reversibility tiers:
#
#   reversible            — feature flag flip, easy rollback
#   semi_reversible       — rollback costs money / contracts / friction
#   irreversible          — headcount cuts, contract cancellations, infra
#
# Verdict matrix:
#
#   missing required field             -> incomplete
#   irreversible + tier < independent  -> fail
#   irreversible + tier < our_pilot    -> warn
#   semi_reversible + tier < funded    -> warn
#   else                               -> pass
#
# Companion to Bashmatica! Issue #16.
#
# Targets bash 3.2+ (macOS-compatible). Hard dep: jq.

set -euo pipefail

VERSION="0.1.0"

usage() {
  cat <<'EOF'
Usage:
  receipt-check.sh --claims <path>    Score a { "claims": [ ... ] } file
  receipt-check.sh --list <path>      Score a flat JSON array of claim objects
  receipt-check.sh --example          Run against the bundled example claims

Options:
  --format <fmt>     markdown (default) | json | csv
  --strict           Exit non-zero on any fail/incomplete verdict
  --ci               Alias for --strict --format markdown
  -h, --help         Show this help
  --version          Print version

Claim object shape:
  {
    "claim": "47% faster ticket triage",          (required)
    "vendor": "Acme Triage AI",
    "source_url": "https://...",
    "source_type": "vendor_case_study",           (required; see tiers above)
    "sample_size": 23,
    "timeframe_weeks": 4,
    "deployment_scale": "one 5-person team",
    "regression_rate": null,
    "our_deployment_scale": "support org of 2400",
    "decision_reversibility": "irreversible",     (required)
    "decision_description": "headcount reduction"
  }

Required-field rules:
  - Always required: claim, source_type, decision_reversibility
  - Required unless source_type == "vendor_demo":
      sample_size, timeframe_weeks, deployment_scale

Examples:
  receipt-check.sh --example
  receipt-check.sh --claims ./procurement-claims.json --strict
  receipt-check.sh --list ./claims.json --format json | jq .

YAML authoring is supported via yq:
  yq -o=json claims.yaml | receipt-check.sh --list /dev/stdin --strict
EOF
}

# Tier rank table; higher = stronger evidence.
tier_rank() {
  case "$1" in
    vendor_demo)         echo 1 ;;
    vendor_case_study)   echo 2 ;;
    vendor_funded_study) echo 3 ;;
    independent_study)   echo 4 ;;
    our_pilot)           echo 5 ;;
    *)                   echo 0 ;;
  esac
}

reversibility_rank() {
  case "$1" in
    reversible)      echo 1 ;;
    semi_reversible) echo 2 ;;
    irreversible)    echo 3 ;;
    *)               echo 0 ;;
  esac
}

# Placeholder for null/missing fields. Used so jq's @tsv output never contains
# consecutive tabs (which bash `read -r` collapses when IFS is whitespace).
NONE="__none__"

is_none() {
  [[ -z "$1" || "$1" == "null" || "$1" == "$NONE" ]]
}

# Args: source_type sample_size timeframe_weeks deployment_scale reversibility claim
# Emits required-field gaps, comma-separated, or "-" if complete.
missing_fields() {
  local stype="$1" ssize="$2" tweeks="$3" dscale="$4" rev="$5" claim="$6"
  local gaps=""

  is_none "$claim" && gaps="${gaps}claim,"
  is_none "$stype" && gaps="${gaps}source_type,"
  is_none "$rev"   && gaps="${gaps}decision_reversibility,"

  # For anything beyond vendor_demo, the supporting evidence needs scale + size
  # + timeframe. vendor_demo is exempt: there's no production data to size.
  if ! is_none "$stype" && [[ "$stype" != "vendor_demo" ]]; then
    is_none "$ssize"  && gaps="${gaps}sample_size,"
    is_none "$tweeks" && gaps="${gaps}timeframe_weeks,"
    is_none "$dscale" && gaps="${gaps}deployment_scale,"
  fi

  if [[ -z "$gaps" ]]; then
    echo "-"
  else
    echo "${gaps%,}"
  fi
}

# Args: source_type reversibility missing
# Emits: verdict reason
classify_claim() {
  local stype="$1" rev="$2" gaps="$3"
  local trank rrank verdict reason

  if [[ "$gaps" != "-" ]]; then
    echo -e "incomplete\tmissing: $gaps"
    return
  fi

  trank=$(tier_rank "$stype")
  rrank=$(reversibility_rank "$rev")

  if [[ "$trank" -eq 0 ]]; then
    echo -e "incomplete\tunknown source_type: $stype"
    return
  fi
  if [[ "$rrank" -eq 0 ]]; then
    echo -e "incomplete\tunknown decision_reversibility: $rev"
    return
  fi

  if [[ "$rrank" -eq 3 && "$trank" -lt 4 ]]; then
    verdict="fail"
    reason="irreversible decision backed only by vendor-sourced evidence; require independent_study or own pilot before commit"
  elif [[ "$rrank" -eq 3 && "$trank" -lt 5 ]]; then
    verdict="warn"
    reason="irreversible decision lacks production-scale receipt; run a reversible pilot at your scale first"
  elif [[ "$rrank" -eq 2 && "$trank" -lt 3 ]]; then
    verdict="warn"
    reason="semi-reversible decision relies on vendor-controlled evidence; cost of rollback is non-trivial"
  else
    verdict="pass"
    reason="receipt tier appropriate to decision reversibility"
  fi

  echo -e "${verdict}\t${reason}"
}

# Read JSON and emit normalized stream of one claim per line:
#   <verdict>\t<reason>\t<tier>\t<reversibility>\t<vendor>\t<claim>\t<missing>
normalize_and_classify() {
  local input_path="$1" shape="$2"
  local jq_filter

  if [[ "$shape" == "claims" ]]; then
    jq_filter='.claims[]'
  else
    jq_filter='.[]'
  fi

  # Every field falls back to NONE so jq @tsv never produces consecutive tabs
  # (bash `read -r` with IFS=$'\t' collapses runs of whitespace IFS chars).
  jq -r --arg none "$NONE" "$jq_filter | [
    (.claim // \$none),
    (.vendor // \$none),
    (.source_type // \$none),
    ((.sample_size // \$none) | tostring),
    ((.timeframe_weeks // \$none) | tostring),
    (.deployment_scale // \$none),
    (.decision_reversibility // \$none)
  ] | @tsv" "$input_path" | while IFS=$'\t' read -r claim vendor stype ssize tweeks dscale rev; do
    local gaps result verdict reason
    gaps=$(missing_fields "$stype" "$ssize" "$tweeks" "$dscale" "$rev" "$claim")
    result=$(classify_claim "$stype" "$rev" "$gaps")
    verdict=$(printf '%s' "$result" | cut -f1)
    reason=$(printf '%s' "$result" | cut -f2)
    # Strip placeholders from display fields so output stays human-readable.
    is_none "$stype"  && stype=""
    is_none "$rev"    && rev=""
    is_none "$vendor" && vendor=""
    is_none "$claim"  && claim=""
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$verdict" "$reason" "$stype" "$rev" "$vendor" "$claim" "$gaps"
  done
}

emit_markdown() {
  local classified="$1"
  local total n_pass n_warn n_fail n_incomp
  total=$(printf '%s\n' "$classified" | grep -c . || true)
  n_pass=$(printf '%s\n'   "$classified" | awk -F'\t' '$1=="pass"'       | wc -l | tr -d ' ')
  n_warn=$(printf '%s\n'   "$classified" | awk -F'\t' '$1=="warn"'       | wc -l | tr -d ' ')
  n_fail=$(printf '%s\n'   "$classified" | awk -F'\t' '$1=="fail"'       | wc -l | tr -d ' ')
  n_incomp=$(printf '%s\n' "$classified" | awk -F'\t' '$1=="incomplete"' | wc -l | tr -d ' ')

  echo "# receipt-check scorecard"
  echo
  echo "## Summary"
  echo
  echo "- Total claims: $total"
  echo "- pass: $n_pass"
  echo "- warn: $n_warn"
  echo "- fail: $n_fail"
  echo "- incomplete: $n_incomp"
  echo
  if [[ "$n_fail" -gt 0 || "$n_incomp" -gt 0 ]]; then
    echo "**${n_fail} fail / ${n_incomp} incomplete.** Do not commit irreversible decisions on these claims."
    echo
  fi
  echo "## Per-claim verdicts"
  echo
  echo "| Verdict | Vendor | Claim | Source tier | Reversibility | Notes |"
  echo "|---------|--------|-------|-------------|---------------|-------|"
  printf '%s\n' "$classified" | awk -F'\t' '
    {
      verdict = toupper($1)
      printf "| %s | %s | %s | %s | %s | %s |\n", verdict, $5, $6, $3, $4, $2
    }'
}

emit_json() {
  local classified="$1"
  printf '%s\n' "$classified" | awk -F'\t' '
    BEGIN { printf "[\n" }
    NR>1  { printf ",\n" }
          { gsub(/"/, "\\\"", $6); gsub(/"/, "\\\"", $2);
            printf "  {\"verdict\":\"%s\",\"vendor\":\"%s\",\"claim\":\"%s\",\"source_type\":\"%s\",\"decision_reversibility\":\"%s\",\"reason\":\"%s\",\"missing\":\"%s\"}",
                   $1, $5, $6, $3, $4, $2, $7 }
    END   { printf "\n]\n" }'
}

emit_csv() {
  local classified="$1"
  echo "verdict,vendor,claim,source_type,decision_reversibility,reason,missing"
  printf '%s\n' "$classified" | awk -F'\t' '
    {
      gsub(/"/, "\"\"", $6); gsub(/"/, "\"\"", $2)
      printf "%s,\"%s\",\"%s\",%s,%s,\"%s\",%s\n", $1, $5, $6, $3, $4, $2, $7
    }'
}

strict_check() {
  local classified="$1"
  local fails
  fails=$(printf '%s\n' "$classified" | awk -F'\t' '$1=="fail" || $1=="incomplete"' | wc -l | tr -d ' ')
  if [[ "$fails" -gt 0 ]]; then
    return 1
  fi
  return 0
}

main() {
  local input_path="" shape="" format="markdown" strict=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --claims)  input_path="$2"; shape="claims"; shift 2 ;;
      --list)    input_path="$2"; shape="list"; shift 2 ;;
      --example)
        local script_dir
        script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
        input_path="$script_dir/examples/sample-claims.json"
        shape="claims"
        shift ;;
      --format)  format="$2"; shift 2 ;;
      --strict)  strict=1; shift ;;
      --ci)      strict=1; format="markdown"; shift ;;
      --version) echo "$VERSION"; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      *)         echo "Unknown flag: $1" >&2; usage; exit 2 ;;
    esac
  done

  if [[ -z "$input_path" ]]; then
    usage; exit 2
  fi

  if [[ ! -f "$input_path" && "$input_path" != "/dev/stdin" ]]; then
    echo "Input file not found: $input_path" >&2
    exit 2
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "receipt-check requires jq. Install with: brew install jq" >&2
    exit 2
  fi

  local classified
  classified=$(normalize_and_classify "$input_path" "$shape")

  case "$format" in
    markdown) emit_markdown "$classified" ;;
    json)     emit_json "$classified" ;;
    csv)      emit_csv "$classified" ;;
    *)        echo "Unknown format: $format" >&2; exit 2 ;;
  esac

  if [[ "$strict" -eq 1 ]]; then
    if ! strict_check "$classified"; then
      echo >&2
      echo "STRICT MODE: at least one fail/incomplete verdict. Exit 1." >&2
      exit 1
    fi
  fi
}

main "$@"

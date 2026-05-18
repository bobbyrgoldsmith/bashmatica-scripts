#!/usr/bin/env bash
# agent-net — classify an agent's tool manifest by reversibility tier.
#
# Reads an MCP `tools/list` response OR a flat JSON array of tool definitions
# and classifies each tool into one of four reversibility tiers:
#
#   read-only               — no external write; worst case is exposed data
#   reversible-write        — internal write with a clear undo path
#   irreversible-action     — outbound or external state change w/o easy undo
#   privileged-blast-radius — touches money, contracts, or counterparty action
#
# Conservative-by-default: ambiguous tools land one tier up. Cost of
# over-classification is a confirmation click; cost of under-classification
# is an unrecoverable action.
#
# Companion to Bashmatica! Issue #15.
#
# Targets bash 3.2+ (macOS-compatible). Hard dep: jq.

set -euo pipefail

VERSION="0.1.0"

usage() {
  cat <<'EOF'
Usage:
  agent-net.sh --manifest <path>   Classify an MCP `tools/list` response
  agent-net.sh --list <path>       Classify a flat JSON array of tool objects
  agent-net.sh --example           Run against the bundled example manifest

Options:
  --format <fmt>     markdown (default) | json | csv
  --strict           Exit non-zero if any tool above reversible-write lacks
                     `requires_confirmation: true` in its definition
  --ci               Alias for --strict --format markdown
  -h, --help         Show this help
  --version          Print version

Input shape:
  --manifest expects { "tools": [ { "name": ..., "description": ...,
                                    "inputSchema": {...},
                                    "requires_confirmation"?: bool }, ... ] }
  --list expects the array directly: [ { ... }, { ... } ]

Examples:
  agent-net.sh --example
  agent-net.sh --manifest ./manifest.json --strict
  agent-net.sh --list ./tools.json --format json | jq .
EOF
}

# Classification patterns. Tiers are evaluated highest-risk first.
# Patterns are verb-anchored where possible: object-presence alone
# (e.g. "invoice" in "list_invoices") shouldn't trigger the top tier;
# action context (e.g. "send_invoice", "wire") should.
PATTERN_PRIVILEGED='wire|\bach\b|docusign|charge[^a-z]|refund|terminate|delete[_-]?account|revoke[_-]?access|grant[_-]?access|provision|send[_-]?invoice|sign[_-]?contract|cancel[_-]?subscription'
PATTERN_IRREVERSIBLE='send|post|publish|notify|deploy|broadcast|email|sms|webhook|schedule[_-]?meeting|create[_-]?(user|customer|order|account)|delete'
PATTERN_REVERSIBLE='draft|save|update|write|store|cache|set|patch|upsert|tag|label|annotate'

classify_tool() {
  # Args: name desc schema_json
  # Patterns match on the tool NAME only. Descriptions often reference other
  # tools ("until send_invoice is called"); schemas contain enum values that
  # aren't actions. Tool names should disclose the action — if they don't,
  # the tool is named badly and the operator should fix the name, not the
  # classifier.
  local name="$1" desc="$2" schema="$3"
  local haystack tier signals
  haystack=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

  if printf '%s' "$haystack" | grep -qE "$PATTERN_PRIVILEGED"; then
    tier="privileged-blast-radius"
    signals="money/counterparty/identity"
  elif printf '%s' "$haystack" | grep -qE "$PATTERN_IRREVERSIBLE"; then
    tier="irreversible-action"
    signals="outbound/external-state"
  elif printf '%s' "$haystack" | grep -qE "$PATTERN_REVERSIBLE"; then
    tier="reversible-write"
    signals="internal-write"
  else
    tier="read-only"
    signals="none-detected"
  fi

  printf '%s\t%s\t%s\n' "$tier" "$signals" "$name"
}

# Read input JSON and emit a normalized stream of one tool per line:
#   <tier>\t<signals>\t<name>\t<requires_confirmation>
normalize_and_classify() {
  local input_path="$1" shape="$2"
  local jq_filter

  if [[ "$shape" == "manifest" ]]; then
    jq_filter='.tools[]'
  else
    jq_filter='.[]'
  fi

  jq -r --arg fmt 'one' "$jq_filter | [
    (.name // \"<unnamed>\"),
    (.description // \"\"),
    (.inputSchema // .input_schema // {} | tostring),
    (.requires_confirmation // false | tostring)
  ] | @tsv" "$input_path" | while IFS=$'\t' read -r name desc schema confirm; do
    local result tier signals
    result=$(classify_tool "$name" "$desc" "$schema")
    tier=$(printf '%s' "$result" | cut -f1)
    signals=$(printf '%s' "$result" | cut -f2)
    printf '%s\t%s\t%s\t%s\n' "$tier" "$signals" "$name" "$confirm"
  done
}

emit_markdown() {
  local classified="$1"
  local total
  total=$(printf '%s\n' "$classified" | grep -c . || true)

  local n_read n_rev n_irr n_priv
  n_read=$(printf '%s\n' "$classified" | awk -F'\t' '$1=="read-only"' | wc -l | tr -d ' ')
  n_rev=$(printf '%s\n' "$classified" | awk -F'\t' '$1=="reversible-write"' | wc -l | tr -d ' ')
  n_irr=$(printf '%s\n' "$classified" | awk -F'\t' '$1=="irreversible-action"' | wc -l | tr -d ' ')
  n_priv=$(printf '%s\n' "$classified" | awk -F'\t' '$1=="privileged-blast-radius"' | wc -l | tr -d ' ')

  local missing_conf
  missing_conf=$(printf '%s\n' "$classified" | awk -F'\t' '
    ($1=="irreversible-action" || $1=="privileged-blast-radius") && $4!="true"' | wc -l | tr -d ' ')

  echo "# agent-net scorecard"
  echo
  echo "## Summary"
  echo
  echo "- Total tools: $total"
  echo "- read-only: $n_read"
  echo "- reversible-write: $n_rev"
  echo "- irreversible-action: $n_irr"
  echo "- privileged-blast-radius: $n_priv"
  echo
  if [[ "$missing_conf" -gt 0 ]]; then
    echo "**${missing_conf} tool(s) above reversible-write lack \`requires_confirmation: true\`.**"
    echo
  fi
  echo "## Per-tool classification"
  echo
  echo "| Tool | Tier | Signals | requires_confirmation |"
  echo "|------|------|---------|------------------------|"
  printf '%s\n' "$classified" | awk -F'\t' '
    {
      conf = ($4 == "true") ? "yes" : (($1 == "read-only" || $1 == "reversible-write") ? "n/a" : "MISSING")
      printf "| %s | %s | %s | %s |\n", $3, $1, $2, conf
    }'
}

emit_json() {
  local classified="$1"
  printf '%s\n' "$classified" | awk -F'\t' '
    BEGIN { printf "[\n" }
    NR>1  { printf ",\n" }
          { printf "  {\"name\":\"%s\",\"tier\":\"%s\",\"signals\":\"%s\",\"requires_confirmation\":%s}",
                   $3, $1, $2, $4 }
    END   { printf "\n]\n" }'
}

emit_csv() {
  local classified="$1"
  echo "name,tier,signals,requires_confirmation"
  printf '%s\n' "$classified" | awk -F'\t' '{ printf "%s,%s,%s,%s\n", $3, $1, $2, $4 }'
}

strict_check() {
  local classified="$1"
  local fails
  fails=$(printf '%s\n' "$classified" | awk -F'\t' '
    ($1=="irreversible-action" || $1=="privileged-blast-radius") && $4!="true"' | wc -l | tr -d ' ')
  if [[ "$fails" -gt 0 ]]; then
    return 1
  fi
  return 0
}

main() {
  local input_path="" shape="" format="markdown" strict=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest) input_path="$2"; shape="manifest"; shift 2 ;;
      --list)     input_path="$2"; shape="list"; shift 2 ;;
      --example)
        local script_dir
        script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
        input_path="$script_dir/examples/sample-mcp-manifest.json"
        shape="manifest"
        shift ;;
      --format)   format="$2"; shift 2 ;;
      --strict)   strict=1; shift ;;
      --ci)       strict=1; format="markdown"; shift ;;
      --version)  echo "$VERSION"; exit 0 ;;
      -h|--help)  usage; exit 0 ;;
      *)          echo "Unknown flag: $1" >&2; usage; exit 2 ;;
    esac
  done

  if [[ -z "$input_path" ]]; then
    usage; exit 2
  fi

  if [[ ! -f "$input_path" ]]; then
    echo "Input file not found: $input_path" >&2
    exit 2
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "agent-net requires jq. Install with: brew install jq" >&2
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
      echo "STRICT MODE: at least one irreversible/privileged tool lacks requires_confirmation. Exit 1." >&2
      exit 1
    fi
  fi
}

main "$@"

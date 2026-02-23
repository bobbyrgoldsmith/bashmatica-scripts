#!/usr/bin/env bash
# compare_llm_models.sh - Compare Claude model tiers on your log data
# From Bashmatica! #3: Not All LLMs Are Equal for DevOps Tasks
# https://github.com/bobbyrgoldsmith/bashmatica-scripts

set -euo pipefail

ANTHROPIC_API_VERSION="2023-06-01"
MAX_TOKENS=1000

usage() {
    echo "Usage: $0 <prompt> [log_file]"
    echo ""
    echo "Compare Claude Sonnet vs Haiku responses for the same input."
    echo "Reads from log_file or stdin."
    echo ""
    echo "Requires: ANTHROPIC_API_KEY, curl, jq"
    exit 1
}

query_model() {
    local model="$1" prompt="$2" log_snippet="$3"
    curl -s https://api.anthropic.com/v1/messages \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "content-type: application/json" \
        -H "anthropic-version: $ANTHROPIC_API_VERSION" \
        -d "$(jq -n \
            --arg p "$prompt" \
            --arg l "$log_snippet" \
            --arg m "$model" \
            --argjson t "$MAX_TOKENS" \
            '{
                model: $m,
                max_tokens: $t,
                messages: [{role: "user", content: "\($p)\n\n\($l)"}]
            }')" | jq -r '.content[0].text'
}

[[ $# -lt 1 ]] && usage
[[ -z "${ANTHROPIC_API_KEY:-}" ]] && { echo "Error: ANTHROPIC_API_KEY not set" >&2; exit 1; }
command -v jq >/dev/null || { echo "Error: jq is required" >&2; exit 1; }
command -v curl >/dev/null || { echo "Error: curl is required" >&2; exit 1; }

prompt="$1"

if [[ $# -ge 2 && -f "$2" ]]; then
    log_snippet=$(cat "$2")
elif [[ ! -t 0 ]]; then
    log_snippet=$(cat)
else
    echo "Error: Provide a log file or pipe input via stdin" >&2
    usage
fi

echo "=== Claude Sonnet (claude-sonnet-4-6) ==="
time query_model "claude-sonnet-4-6" "$prompt" "$log_snippet"

echo ""
echo "=== Claude Haiku (claude-haiku-4-5-20251001) ==="
time query_model "claude-haiku-4-5-20251001" "$prompt" "$log_snippet"

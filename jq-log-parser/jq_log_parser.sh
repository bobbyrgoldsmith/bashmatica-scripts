#!/usr/bin/env bash
# jq_log_parser.sh - Structured JSON log parsing utilities
# From Bashmatica! Issue #4: When "AI-Native" Means "40% Fewer of You"
# https://github.com/bobbyrgoldsmith/bashmatica-scripts

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: jq_log_parser.sh <command> [options] <file|->

Commands:
  errors-by-service    Count errors grouped by service, sorted by frequency
  errors-by-time       Count errors grouped by hour
  error-summary        Top errors with service, count, and latest timestamp
  slow-requests        Find requests exceeding a duration threshold

Options:
  -n, --limit NUM      Limit output to NUM results (default: 20)
  -l, --level LEVEL    Log level to filter on (default: error)
  -t, --threshold MS   Duration threshold in ms for slow-requests (default: 1000)
  -h, --help           Show this help

Input:
  Accepts a file path or stdin (use - for stdin).
  Expects JSON logs with one object per line (JSONL format).

Common fields expected:
  .level       Log level (error, warn, info, debug)
  .service     Service or application name
  .timestamp   ISO 8601 timestamp
  .message     Log message text
  .duration    Request duration in ms (for slow-requests)

Examples:
  jq_log_parser.sh errors-by-service /var/log/app/app.json
  cat /var/log/app/*.json | jq_log_parser.sh errors-by-service -
  jq_log_parser.sh slow-requests -t 500 -n 10 /var/log/app/app.json
  jq_log_parser.sh error-summary /var/log/app/app.json | sanitize_for_llm
EOF
}

LIMIT=20
LEVEL="error"
THRESHOLD=1000
COMMAND=""
INPUT=""

parse_args() {
    if [[ $# -lt 1 ]]; then
        usage
        exit 1
    fi

    COMMAND="$1"
    shift

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--limit)
                LIMIT="$2"
                shift 2
                ;;
            -l|--level)
                LEVEL="$2"
                shift 2
                ;;
            -t|--threshold)
                THRESHOLD="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                INPUT="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$INPUT" ]]; then
        INPUT="-"
    fi
}

get_input() {
    if [[ "$INPUT" == "-" ]]; then
        cat
    else
        cat "$INPUT"
    fi
}

errors_by_service() {
    get_input \
        | jq -r "select(.level == \"$LEVEL\") | .service // \"unknown\"" \
        | sort | uniq -c | sort -rn | head -"$LIMIT"
}

errors_by_time() {
    get_input \
        | jq -r "select(.level == \"$LEVEL\") | .timestamp" \
        | sed 's/T\(..\).*/T\1/' \
        | sort | uniq -c | sort -rn | head -"$LIMIT"
}

error_summary() {
    get_input \
        | jq -s "
            [.[] | select(.level == \"$LEVEL\")]
            | group_by(.service // \"unknown\")
            | map({
                service: .[0].service // \"unknown\",
                count: length,
                latest: (sort_by(.timestamp) | last | .timestamp),
                sample_message: .[0].message
            })
            | sort_by(-.count)
            | .[:$LIMIT]
            | .[]
        " \
        | jq -s '.'
}

slow_requests() {
    get_input \
        | jq -r "select(.duration != null and .duration > $THRESHOLD)
            | [.timestamp, .service // \"unknown\", (.duration | tostring) + \"ms\", .message // \"no message\"]
            | @tsv" \
        | sort -t$'\t' -k3 -rn | head -"$LIMIT"
}

main() {
    parse_args "$@"

    if ! command -v jq &>/dev/null; then
        echo "Error: jq is required but not installed." >&2
        echo "Install: brew install jq (macOS) or apt-get install jq (Debian/Ubuntu)" >&2
        exit 1
    fi

    case "$COMMAND" in
        errors-by-service)
            errors_by_service
            ;;
        errors-by-time)
            errors_by_time
            ;;
        error-summary)
            error_summary
            ;;
        slow-requests)
            slow_requests
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown command: $COMMAND" >&2
            usage
            exit 1
            ;;
    esac
}

main "$@"

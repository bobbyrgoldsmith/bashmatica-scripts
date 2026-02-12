#!/bin/bash
#
# llm-sanitizer: Strip secrets from logs before sending to LLMs
# Part of bashmatica-scripts by Nodebridge Automation Solutions
# https://github.com/bobbyrgoldsmith/bashmatica-scripts
#
# Usage:
#   cat /var/log/app/error.log | ./sanitize.sh
#   ./sanitize.sh < logfile.txt
#   ./sanitize.sh logfile.txt
#   kubectl logs pod-name | ./sanitize.sh | llm "analyze these errors"
#
# Options:
#   -v, --verbose    Show what was redacted (to stderr)
#   -c, --config     Use custom patterns file
#   -h, --help       Show this help message
#
# The goal isn't perfection; it's catching the obvious leaks before
# they leave your network.

set -euo pipefail

VERSION="1.0.0"
VERBOSE=false
CUSTOM_PATTERNS=""

# Colors for verbose output (to stderr)
RED='\033[0;31m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
llm-sanitizer v${VERSION}
Strip secrets from logs before sending to LLMs

Usage:
    cat logfile.txt | $(basename "$0") [options]
    $(basename "$0") [options] < logfile.txt
    $(basename "$0") [options] logfile.txt

Options:
    -v, --verbose    Show redaction summary to stderr
    -c, --config     Path to custom patterns file (one regex per line)
    -h, --help       Show this help message
    --version        Show version

Examples:
    # Basic usage
    cat /var/log/app/error.log | ./sanitize.sh

    # Pipe to Claude CLI
    cat error.log | ./sanitize.sh | llm "explain these errors"

    # With verbose output
    kubectl logs my-pod | ./sanitize.sh -v 2>/dev/null | pbcopy

    # Using custom patterns
    ./sanitize.sh -c ./my-patterns.txt < production.log

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -c|--config)
            CUSTOM_PATTERNS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        --version)
            echo "llm-sanitizer v${VERSION}"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            # Assume it's a file
            if [[ -f "$1" ]]; then
                INPUT_FILE="$1"
            else
                echo "File not found: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Build the sed command with all patterns
sanitize() {
    local input="$1"
    local redaction_counts=""

    # Core patterns - these catch the most common leaks
    local result
    result=$(echo "$input" | sed -E \
        -e 's/([Pp]assword[=:]["'"'"']?)[^"'"'"'[:space:]]+/\1[REDACTED]/g' \
        -e 's/([Pp]wd[=:]["'"'"']?)[^"'"'"'[:space:]]+/\1[REDACTED]/g' \
        -e 's/([Aa]pi[_-]?[Kk]ey[=:]["'"'"']?)[A-Za-z0-9_-]{16,}/\1[REDACTED]/g' \
        -e 's/([Tt]oken[=:]["'"'"']?)[A-Za-z0-9_.-]{20,}/\1[REDACTED]/g' \
        -e 's/([Ss]ecret[=:]["'"'"']?)[^"'"'"'[:space:]]+/\1[REDACTED]/g' \
        -e 's/([Cc]redential[s]?[=:]["'"'"']?)[^"'"'"'[:space:]]+/\1[REDACTED]/g' \
        -e 's/Bearer [A-Za-z0-9_.-]+/Bearer [REDACTED]/g' \
        -e 's/Basic [A-Za-z0-9+/=]+/Basic [REDACTED]/g' \
        -e 's/([Cc]onnection[Ss]tring[=:]["'"'"']?)[^"'"'"'[:space:]]+/\1[REDACTED]/g' \
        \
        `# AWS patterns` \
        -e 's/AKIA[0-9A-Z]{16}/[AWS_ACCESS_KEY]/g' \
        -e 's/(AWS_SECRET_ACCESS_KEY[=:][[:space:]]*)[A-Za-z0-9/+=]+/\1[REDACTED]/g' \
        -e 's/([Aa]ws[_-]?[Ss]ecret[_-]?[Aa]ccess[_-]?[Kk]ey[=:][[:space:]]*)[A-Za-z0-9/+=]{20,}/\1[REDACTED]/g' \
        -e 's/[a-z0-9]{32}\.execute-api\.[a-z0-9-]+\.amazonaws\.com/[AWS_API_GATEWAY]/g' \
        \
        `# GCP patterns` \
        -e 's/AIza[0-9A-Za-z_-]{30,}/[GCP_API_KEY]/g' \
        -e 's/[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com/[GCP_CLIENT_ID]/g' \
        -e 's/ya29\.[0-9A-Za-z_-]+/[GCP_ACCESS_TOKEN]/g' \
        \
        `# Azure patterns` \
        -e 's/[a-z0-9]{8}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{12}/[UUID]/g' \
        -e 's/DefaultEndpointsProtocol=[^;]+;AccountName=[^;]+;AccountKey=[^;]+;EndpointSuffix=[^"'"'"'[:space:]]+/[AZURE_STORAGE_CONNECTION]/g' \
        \
        `# GitHub patterns` \
        -e 's/ghp_[A-Za-z0-9]{36}/[GITHUB_PAT]/g' \
        -e 's/gho_[A-Za-z0-9]{36}/[GITHUB_OAUTH]/g' \
        -e 's/ghu_[A-Za-z0-9]{36}/[GITHUB_USER_TOKEN]/g' \
        -e 's/ghs_[A-Za-z0-9]{36}/[GITHUB_SERVER_TOKEN]/g' \
        -e 's/ghr_[A-Za-z0-9]{36}/[GITHUB_REFRESH_TOKEN]/g' \
        \
        `# Stripe patterns` \
        -e 's/sk_live_[A-Za-z0-9]{24,}/[STRIPE_SECRET_KEY]/g' \
        -e 's/sk_test_[A-Za-z0-9]{24,}/[STRIPE_TEST_KEY]/g' \
        -e 's/pk_live_[A-Za-z0-9]{24,}/[STRIPE_PUBLISHABLE_KEY]/g' \
        -e 's/pk_test_[A-Za-z0-9]{24,}/[STRIPE_TEST_PUBLISHABLE]/g' \
        -e 's/rk_live_[A-Za-z0-9]{24,}/[STRIPE_RESTRICTED_KEY]/g' \
        \
        `# Slack patterns` \
        -e 's/xox[baprs]-[A-Za-z0-9-]+/[SLACK_TOKEN]/g' \
        -e 's/https:\/\/hooks\.slack\.com\/services\/[A-Za-z0-9/]+/[SLACK_WEBHOOK]/g' \
        \
        `# Database connection strings - handle passwords containing @ by matching to last @ before host` \
        -e 's#mongodb(\+srv)?://([^:]+):(.*)@(localhost|[0-9]+\.|[a-zA-Z][a-zA-Z0-9.-]*[.:])#mongodb\1://[USER]:[REDACTED]@\4#g' \
        -e 's#postgres(ql)?://([^:]+):(.*)@(localhost|[0-9]+\.|[a-zA-Z][a-zA-Z0-9.-]*[.:])#postgres\1://[USER]:[REDACTED]@\4#g' \
        -e 's#mysql://([^:]+):(.*)@(localhost|[0-9]+\.|[a-zA-Z][a-zA-Z0-9.-]*[.:])#mysql://[USER]:[REDACTED]@\3#g' \
        -e 's#redis://([^:]+):(.*)@(localhost|[0-9]+\.|[a-zA-Z][a-zA-Z0-9.-]*[.:])#redis://[USER]:[REDACTED]@\3#g' \
        -e 's#amqp://([^:]+):(.*)@(localhost|[0-9]+\.|[a-zA-Z][a-zA-Z0-9.-]*[.:])#amqp://[USER]:[REDACTED]@\3#g' \
        \
        `# Generic JWT (don't redact entirely, just the signature)` \
        -e 's/(eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.)[A-Za-z0-9_-]+/\1[SIGNATURE_REDACTED]/g' \
        \
        `# Private keys` \
        -e 's/-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----/[PRIVATE_KEY_REDACTED]/g' \
        -e 's/-----BEGIN CERTIFICATE-----/[CERTIFICATE_REDACTED]/g' \
        \
        `# Email addresses (partially redact)` \
        -e 's/\b([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Z|a-z]{2,})\b/\1***@\2/g' \
        \
        `# IP addresses (internal ranges)` \
        -e 's|10\.[0-9]+\.[0-9]+\.[0-9]+|[INTERNAL_IP]|g' \
        -e 's|172\.1[6-9]\.[0-9]+\.[0-9]+|[INTERNAL_IP]|g' \
        -e 's|172\.2[0-9]\.[0-9]+\.[0-9]+|[INTERNAL_IP]|g' \
        -e 's|172\.3[0-1]\.[0-9]+\.[0-9]+|[INTERNAL_IP]|g' \
        -e 's|192\.168\.[0-9]+\.[0-9]+|[INTERNAL_IP]|g' \
        \
        `# Common environment variable patterns - match until end of line or quote` \
        -e 's/(DATABASE_URL=)[^[:space:]"'"'"']+/\1[REDACTED]/g' \
        -e 's/(REDIS_URL=)[^[:space:]"'"'"']+/\1[REDACTED]/g' \
        -e 's/(SESSION_SECRET=)[^[:space:]"'"'"']+/\1[REDACTED]/g' \
        -e 's/(ENCRYPTION_KEY=)[^[:space:]"'"'"']+/\1[REDACTED]/g' \
        -e 's/(PRIVATE_KEY=)[^[:space:]"'"'"']+/\1[REDACTED]/g' \
    )

    echo "$result"
}

# Process custom patterns if provided
apply_custom_patterns() {
    local input="$1"
    local patterns_file="$2"

    if [[ -f "$patterns_file" ]]; then
        local result="$input"
        while IFS= read -r pattern || [[ -n "$pattern" ]]; do
            # Skip empty lines and comments
            [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue
            result=$(echo "$result" | sed -E "s/${pattern}/[CUSTOM_REDACTED]/g")
        done < "$patterns_file"
        echo "$result"
    else
        echo "$input"
    fi
}

# Count redactions for verbose mode
count_redactions() {
    local original="$1"
    local sanitized="$2"

    local count
    count=$(diff <(echo "$original") <(echo "$sanitized") | grep -c "^>" || true)
    echo "$count"
}

# Main execution
main() {
    local input

    # Read from file or stdin
    if [[ -n "${INPUT_FILE:-}" ]]; then
        input=$(cat "$INPUT_FILE")
    else
        input=$(cat)
    fi

    # Sanitize
    local result
    result=$(sanitize "$input")

    # Apply custom patterns if provided
    if [[ -n "$CUSTOM_PATTERNS" ]]; then
        result=$(apply_custom_patterns "$result" "$CUSTOM_PATTERNS")
    fi

    # Verbose output
    if [[ "$VERBOSE" == true ]]; then
        local redaction_count
        redaction_count=$(grep -o '\[REDACTED\]\|\[AWS_[A-Z_]*\]\|\[GCP_[A-Z_]*\]\|\[GITHUB_[A-Z_]*\]\|\[STRIPE_[A-Z_]*\]\|\[SLACK_[A-Z_]*\]\|\[INTERNAL_IP\]\|\[UUID\]\|\[PRIVATE_KEY_REDACTED\]\|\[CERTIFICATE_REDACTED\]\|\[SIGNATURE_REDACTED\]\|\[CUSTOM_REDACTED\]' <<< "$result" | wc -l || echo 0)
        echo -e "${RED}[llm-sanitizer]${NC} Redacted ${redaction_count} potential secrets" >&2
    fi

    echo "$result"
}

main

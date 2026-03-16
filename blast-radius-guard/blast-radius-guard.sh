#!/usr/bin/env bash
set -euo pipefail

# blast-radius-guard: Scan git diffs for destructive patterns
# Use as a pre-commit hook or standalone CI check.
#
# Install as pre-commit hook:
#   cp blast-radius-guard.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# Run standalone against staged changes:
#   ./blast-radius-guard.sh
#
# Run against an arbitrary diff:
#   ./blast-radius-guard.sh --diff "git diff main..feature-branch"
#
# Override (when you genuinely need to commit a destructive pattern):
#   BLAST_RADIUS_ALLOW=1 git commit -m "intentional migration reset"

# --- Configuration ---

# Path to custom patterns file (one regex per line, lines starting with # are ignored)
CUSTOM_PATTERNS_FILE="${BLAST_RADIUS_PATTERNS:-}"

# Built-in patterns: ORM footguns, infrastructure destroyers, filesystem nukes
BUILTIN_PATTERNS=(
  # Infrastructure
  'terraform\s+destroy'
  'pulumi\s+destroy'
  'cdk\s+destroy'
  'aws\s+.*\s+delete-'
  'gcloud\s+.*\s+delete'
  'az\s+.*\s+delete'

  # Database / ORM destructive flags
  '--force'
  '--hard'
  '--accept-data-loss'
  'DROP\s+(TABLE|DATABASE|SCHEMA|INDEX)'
  'TRUNCATE\s+TABLE'
  'DELETE\s+FROM\s+\S+\s*(;|$|WHERE\s+1)'
  'downgrade\s+base'
  'db\s+push\s+--accept-data-loss'
  'drizzle-kit\s+push\s+--force'
  'prisma\s+db\s+push'
  'prisma\s+migrate\s+reset'

  # Git destructive ops
  'git\s+push\s+--force'
  'git\s+push\s+-f\b'
  'git\s+reset\s+--hard'
  'git\s+clean\s+-[a-zA-Z]*f'

  # Filesystem
  'rm\s+-[a-zA-Z]*r[a-zA-Z]*f'
  'rm\s+-[a-zA-Z]*f[a-zA-Z]*r'
  'rm\s+-rf'
  'rmdir\s+--ignore-fail-on-non-empty'

  # Container / orchestration
  'docker\s+system\s+prune\s+-a'
  'kubectl\s+delete\s+(namespace|ns)\b'
)

# --- Functions ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Scan git diffs for destructive patterns that could cause high blast radius incidents.

Options:
  --diff CMD       Use a custom diff command (default: git diff --cached)
  --patterns FILE  Load additional patterns from file (one regex per line)
  --list           Print all active patterns and exit
  --quiet          Suppress explanation, print only matched lines
  -h, --help       Show this help message

Environment:
  BLAST_RADIUS_ALLOW=1    Skip the check (use when the destructive op is intentional)
  BLAST_RADIUS_PATTERNS   Path to custom patterns file

Exit codes:
  0  No destructive patterns found (or BLAST_RADIUS_ALLOW=1)
  1  Destructive pattern(s) detected
  2  Usage error
EOF
}

build_pattern() {
  local combined=""
  for p in "${BUILTIN_PATTERNS[@]}"; do
    if [[ -n "$combined" ]]; then
      combined="${combined}|${p}"
    else
      combined="$p"
    fi
  done

  # Append custom patterns from file if provided
  local pfile="${1:-$CUSTOM_PATTERNS_FILE}"
  if [[ -n "$pfile" && -f "$pfile" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"       # strip inline comments
      line="${line// /}"       # trim (basic)
      [[ -z "$line" ]] && continue
      combined="${combined}|${line}"
    done < "$pfile"
  fi

  echo "($combined)"
}

list_patterns() {
  echo "Active patterns:"
  echo ""
  for p in "${BUILTIN_PATTERNS[@]}"; do
    echo "  $p"
  done
  local pfile="${1:-$CUSTOM_PATTERNS_FILE}"
  if [[ -n "$pfile" && -f "$pfile" ]]; then
    echo ""
    echo "Custom patterns from $pfile:"
    while IFS= read -r line; do
      line="${line%%#*}"
      line="${line// /}"
      [[ -z "$line" ]] && continue
      echo "  $line"
    done < "$pfile"
  fi
}

# --- Parse arguments ---

DIFF_CMD="git diff --cached --unified=0"
QUIET=0
EXTRA_PATTERNS_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --diff)
      [[ $# -lt 2 ]] && { echo "Error: --diff requires an argument"; exit 2; }
      DIFF_CMD="$2"
      shift 2
      ;;
    --patterns)
      [[ $# -lt 2 ]] && { echo "Error: --patterns requires a file path"; exit 2; }
      EXTRA_PATTERNS_FILE="$2"
      shift 2
      ;;
    --list)
      list_patterns "$EXTRA_PATTERNS_FILE"
      exit 0
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

# --- Allow override ---

if [[ "${BLAST_RADIUS_ALLOW:-0}" == "1" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "blast-radius-guard: BLAST_RADIUS_ALLOW=1, skipping check."
  exit 0
fi

# --- Run check ---

PATTERN=$(build_pattern "$EXTRA_PATTERNS_FILE")
DIFF_OUTPUT=$(eval "$DIFF_CMD" 2>/dev/null || true)

if [[ -z "$DIFF_OUTPUT" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "blast-radius-guard: No changes to check."
  exit 0
fi

# Only check added lines (lines starting with +, excluding +++ headers)
ADDED_LINES=$(echo "$DIFF_OUTPUT" | grep '^+' | grep -v '^+++' || true)

if [[ -z "$ADDED_LINES" ]]; then
  [[ "$QUIET" -eq 0 ]] && echo "blast-radius-guard: No added lines to check."
  exit 0
fi

MATCHES=$(echo "$ADDED_LINES" | grep -iE "$PATTERN" || true)

if [[ -n "$MATCHES" ]]; then
  echo ""
  echo "=============================================="
  echo " BLOCKED: Destructive pattern(s) detected"
  echo "=============================================="
  echo ""
  echo "$MATCHES" | while IFS= read -r line; do
    echo "  $line"
  done
  echo ""
  if [[ "$QUIET" -eq 0 ]]; then
    echo "Review the flagged lines above. If this change is intentional:"
    echo "  BLAST_RADIUS_ALLOW=1 git commit -m \"your message\""
    echo ""
  fi
  exit 1
fi

[[ "$QUIET" -eq 0 ]] && echo "blast-radius-guard: No destructive patterns found."
exit 0

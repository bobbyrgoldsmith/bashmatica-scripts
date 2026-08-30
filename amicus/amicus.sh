#!/usr/bin/env bash
# amicus.sh - confirm a human non-author approved a PR; never count a bot as the ratifier.
# usage: amicus.sh <pr-number-or-url>   (run inside the repo, gh authenticated)
set -euo pipefail

PR="${1:?usage: amicus.sh <pr-number-or-url>}"

data="$(gh pr view "$PR" --json author,reviews)"

author="$(jq -r '.author.login' <<<"$data")"

# A valid ratifier is an APPROVED review from a human login that isn't the author.
# GitHub marks automation accounts with a "[bot]" login suffix or a Bot user type.
human_approvals="$(jq -r --arg author "$author" '
  [ .reviews[]
    | select(.state == "APPROVED")
    | select(.author.login != $author)
    | select((.author.login | endswith("[bot]")) | not)
    | .author.login
  ] | unique | .[]' <<<"$data")"

bot_approvals="$(jq -r '
  [ .reviews[]
    | select(.state == "APPROVED")
    | select(.author.login | endswith("[bot]"))
    | .author.login
  ] | unique | .[]' <<<"$data")"

[ -n "$bot_approvals" ] && printf 'note: bot approval present (advisory only): %s\n' "$bot_approvals"

if [ -z "$human_approvals" ]; then
  echo "AMICUS: BLOCKED - no approving review from a human other than the author ($author)."
  echo "The only thing between this diff and main is a machine or the author. Get a second key."
  exit 1
fi

echo "AMICUS: OK - human ratifier(s): $(echo "$human_approvals" | paste -sd, -)"

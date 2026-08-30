#!/usr/bin/env bash
# interlock.sh - refuse bot-authored PRs that lack passing checks or touch a guard.
# usage: interlock.sh OWNER/REPO PR_NUMBER
#   INTERLOCK_CHECKS   comma-separated check names that must have passed (default: test,lint)
#   INTERLOCK_BOTS     regex of bot identities (default matches Copilot, dependabot, *[bot])
#   INTERLOCK_DIFF     path to a diff file; skips gh entirely for offline runs
#   INTERLOCK_PASSED   newline-separated check names to treat as passed (offline only)
set -euo pipefail

repo="${1:-}"; pr="${2:-}"
checks="${INTERLOCK_CHECKS-test,lint}"
bots="${INTERLOCK_BOTS:-copilot|autofix|dependabot|\[bot\]}"
fail() { echo "INTERLOCK: OPEN - $1"; exit 1; }

if [ -n "${INTERLOCK_DIFF:-}" ]; then
  diff_text=$(cat "$INTERLOCK_DIFF"); authors="${INTERLOCK_AUTHORS:-copilot-autofix[bot]}"
  passed="${INTERLOCK_PASSED:-}"
else
  [ -n "$repo" ] && [ -n "$pr" ] || { echo "usage: interlock.sh OWNER/REPO PR_NUMBER"; exit 2; }
  diff_text=$(gh pr diff "$pr" -R "$repo")
  authors=$(gh pr view "$pr" -R "$repo" --json author,commits \
    -q '[.author.login] + [.commits[].authors[].login, .commits[].authors[].name] | unique | .[]')
  passed=$(gh pr checks "$pr" -R "$repo" --json name,state \
    -q '.[] | select(.state=="SUCCESS") | .name')
fi

# Human-only PRs pass straight through; review remains the control for those.
echo "$authors" | grep -qiE "$bots" || { echo "INTERLOCK: CLOSED - no bot author"; exit 0; }

# 1. Every named deterministic check must have actually passed.
IFS=',' read -ra required <<< "$checks"
for c in "${required[@]:-}"; do
  [ -n "$c" ] || continue
  echo "$passed" | grep -qx "$c" || fail "required check '$c' did not pass"
done

# 2. A removed sanitizer/escape line is a guard coming off.
removed=$(echo "$diff_text" | grep -E '^-[^-]' \
  | grep -iE 'saniti[sz]|escape|quote|shellcheck|allowlist|whitelist' || true)
[ -z "$removed" ] || fail "sanitizer removed:"$'\n'"$removed"

# 3. A raw event expansion added inside a workflow run block is script injection.
added=$(echo "$diff_text" | grep -E '^\+[^+]' \
  | grep -E '\$\{\{ *github\.event\.[a-z_.]*(title|body|ref|label|name|message|login)' || true)
[ -z "$added" ] || fail "raw event expansion added:"$'\n'"$added"

echo "INTERLOCK: CLOSED - checks passed, guards intact"

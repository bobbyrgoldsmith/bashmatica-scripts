#!/usr/bin/env bash
# samehand.sh - flag any pipeline step whose proposer is also its ratifier.
# Format: pipe-delimited "step | proposer | ratifier". Blank lines and # comments ignored.

scan() {
  awk -F'|' '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    {
      step=trim($1); proposer=trim($2); ratifier=trim($3)
      if (proposer=="" || ratifier=="") {
        printf "INCOMPLETE  %-16s missing a proposer or a ratifier\n", step; warn++; next
      }
      if (proposer==ratifier) {
        printf "SAME-HAND   %-16s %s proposes AND ratifies\n", step, proposer; fail++
      } else {
        printf "TWO-KEY     %-16s %s -> %s\n", step, proposer, ratifier
      }
    }
    END {
      printf "\nVerdict: "
      if (fail>0)      printf "NOT CLEAN (%d same-hand, %d incomplete)\n", fail, warn+0
      else if (warn>0) printf "INCOMPLETE (%d step(s) missing a key)\n", warn
      else             printf "CLEAN (every step has two distinct keys)\n"
      exit (fail>0 || warn>0) ? 1 : 0
    }
  ' "$1"
}

case "${1:-}" in
  --pipeline) [ -n "${2:-}" ] || { echo "usage: $0 --pipeline FILE"; exit 2; }; scan "$2" ;;
  --example)
    tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
# step             | proposer       | ratifier
deploy_prod        | deploy-agent   | deterministic-gate
db_migration       | migrate-agent  | migrate-agent
refund_batch       | finance-agent  | human:controller
test_autofix       | fixer-agent    | fixer-agent
publish_post       | writer-agent   | editor-human
send_campaign      | outreach-agent |
EOF
    scan "$tmp"; rc=$?; rm -f "$tmp"; exit $rc ;;
  *) echo "usage: $0 --pipeline FILE | --example"; exit 2 ;;
esac

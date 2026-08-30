#!/usr/bin/env bash
# Stand-in model that wobbles the way a batched endpoint does: the phrasing churns
# from run to run, and a few runs grab the wrong number entirely. Deterministic via
# a run counter so the demo prints the same thing every time.
cat >/dev/null
c="${WOBBLY_COUNTER:-/tmp/wobbly-llm.count}"
n=$(cat "$c" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$c"
echo "Reading the invoice."
echo "Subtotal and tax are listed separately."
echo "Summing the lines to check the total."
case $n in
  17|34) echo "The grand total appears to be 100.00" ;;
  50)    echo "Grand total: 100.00" ;;
  *)     case $((n % 5)) in
           0) echo "90.00" ;;
           1) echo "Grand total: 90.00" ;;
           2) echo "The grand total is 90.00." ;;
           3) echo "Total: 90.00" ;;
           4) echo "The invoice total comes to 90.00" ;;
         esac ;;
esac

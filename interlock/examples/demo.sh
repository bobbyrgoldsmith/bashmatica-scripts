#!/usr/bin/env bash
# Run interlock offline against a diff shaped like the June 2026 Snowflake commit (Bashmatica! #29).
cd "$(dirname "$0")"
echo '$ cat snowflake-shaped.diff'; cat snowflake-shaped.diff; echo
echo '$ INTERLOCK_DIFF=snowflake-shaped.diff INTERLOCK_CHECKS=test INTERLOCK_PASSED=test ../interlock.sh'
INTERLOCK_DIFF=snowflake-shaped.diff INTERLOCK_CHECKS=test INTERLOCK_PASSED=test ../interlock.sh
echo "exit=$?"

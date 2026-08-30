#!/usr/bin/env bash
# Reproduce the runaway-agent run from Bashmatica! #28: the token fuse trips first.
cd "$(dirname "$0")/.."
echo '$ MAX_TOKENS=50000 MAX_USD=1 USD_PER_MTOK=15 ./fusebox.sh examples/runaway-agent.sh'
MAX_TOKENS=50000 MAX_USD=1 USD_PER_MTOK=15 ./fusebox.sh examples/runaway-agent.sh
echo "exit=$?"

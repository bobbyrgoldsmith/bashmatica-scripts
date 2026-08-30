#!/usr/bin/env bash
# Reproduce the variance probe from Bashmatica! #26 with a stand-in model that wobbles.
cd "$(dirname "$0")"
export WOBBLY_COUNTER="$(mktemp)"; trap 'rm -f "$WOBBLY_COUNTER"' EXIT
echo "\$ LLM=./wobbly-llm.sh ../holdstill.sh extract.txt 50 '[0-9]+\\.[0-9]{2}'"
LLM=./wobbly-llm.sh ../holdstill.sh extract.txt 50 '[0-9]+\.[0-9]{2}'

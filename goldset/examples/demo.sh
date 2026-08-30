#!/usr/bin/env bash
# Reproduce the cases.tsv run from Bashmatica! #27 with a canned stand-in model.
cd "$(dirname "$0")"
echo '$ cat cases.tsv'; cat cases.tsv; echo
echo '$ LLM=./fake-llm.sh ../goldset.sh cases.tsv'
LLM=./fake-llm.sh ../goldset.sh cases.tsv
echo "exit=$?"

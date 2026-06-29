# log-triage

Read-only CI-log triage: summarize a failed run and classify it (flaky, infra, or
real regression) without ever letting the agent "fix" anything or assert a root
cause as fact.

## The problem

A failed CI run dumps thousands of lines and the one that matters is buried. An
agent is genuinely good at reading that wall of text, and genuinely dangerous when
asked to declare a distributed-system root cause as truth. `log-triage` keeps the
agent on the safe side of that line: it feeds the failing log to an LLM with a
grounded prompt that forces a closed classification, a cited log line as evidence,
and "insufficient evidence" as an allowed answer. It summarizes and triages; it
never edits or ratifies.

## Usage

```bash
./log-triage.sh <logfile> [test-context]
```

It pipes a grounded triage prompt to whatever CLI is set in `$LLM` (default `llm`;
any tool that reads a prompt on stdin works, e.g. `LLM="claude -p"`).

## Requires

- bash 3.2+, and an LLM CLI on `$PATH` (set via `$LLM`)

## From the newsletter

Companion script for [Bashmatica! Issue #24](https://bashmatica.beehiiv.com).
Hand-raiser keyword: `LOGTRIAGE`.

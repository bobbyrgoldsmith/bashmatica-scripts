# ctx-frisk

Refuse to let secret-shaped strings into an agent's context window or
agent-visible logs. A pre-flight scanner you run as a blocking gate.

## The problem

The moment you wire an LLM agent into CI, your env vars, tokens, connection
strings, and proprietary code can flow into the model's context, and from there
into logs, traces, or a provider's retention. `ctx-frisk` scans anything about to
enter an agent's context or be printed to an agent-visible log, redacts the
secret-shaped strings, and exits non-zero so it can gate the step.

## Usage

```bash
./ctx-frisk <file>           # scan a file
some-command | ./ctx-frisk   # scan stdin
```

It prints the input with secrets redacted and exits non-zero if any were found,
so it works as a blocking pre-flight check before an agent reads the data.

## Requires

- python 3.8+

## From the newsletter

Companion script for [Bashmatica! Issue #23](https://bashmatica.beehiiv.com).
Hand-raiser keyword: `FRISK`.

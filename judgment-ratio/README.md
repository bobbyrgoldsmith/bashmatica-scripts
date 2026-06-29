# judgment-ratio

An honest audit of what your automation actually hands off, versus what still
needs a human standing over it.

## The problem

Automating 80% of the steps feels like 80% of the job, but the last slice holds
most of the difficulty and most of the risk, and the easy work you automated was
never the expensive part. `judgment-ratio` makes the real number visible: it reads
a ledger of your pipeline steps and reports how much is genuinely hands-off versus
supervised or reworked.

## Usage

```bash
./judgment-ratio.sh <ledger.tsv>   # defaults to ./pipeline.tsv
```

The ledger is tab-separated, one step per line:

```
step_name	status	human_minutes_per_run
```

`status` is one of `auto` (runs unattended), `supervised` (a human watches the
output), or `rework` (a human routinely fixes the output). It prints your true
hands-off ratio and a verdict.

## Requires

- bash 3.2+, `awk`

## From the newsletter

Companion script for [Bashmatica! Issue #22](https://bashmatica.beehiiv.com).
Hand-raiser keyword: `LEDGER`.

## Related

- [samehand](../samehand/) (#21) — find pipeline steps where the proposer also ratifies.

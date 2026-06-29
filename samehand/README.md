# samehand

Flag any step in a pipeline where the same hand both proposes a change and
ratifies it, so a separate ratifier can be put between the proposal and the
consequence.

## The problem

The moment an agent both authors a consequential action and holds the authority
that releases it, you have collapsed two roles that banks, militaries, and
accounting departments keep deliberately apart. An agent that writes a fix and
also certifies it passing is grading its own paper. An agent that assembles a
refund batch and also authorizes the disbursement is maker and checker in one
account. None of these look dangerous in a demo, because in a demo the agent is
right. The danger is structural, and it cashes in when the agent is wrong and
confident at the same time.

`samehand` takes a plain description of your pipeline, one step per line naming
the proposer and the ratifier, and flags every step where the two are the same
identity, plus any step missing one of the two keys.

## Usage

```bash
./samehand.sh --pipeline ./pipeline.txt   # scan your own pipeline
./samehand.sh --example                    # bundled NOT CLEAN demo
```

Input is pipe-delimited, one step per line. Blank lines and `#` comments are
ignored:

```
# step             | proposer       | ratifier
deploy_prod        | deploy-agent   | deterministic-gate
db_migration       | migrate-agent  | migrate-agent
```

## The verdicts

| Verdict | What it means |
|---------|---------------|
| `TWO-KEY` | The step has two distinct keys: one identity proposes, a different one ratifies. This is the goal. |
| `SAME-HAND` | The proposer and the ratifier are the same identity. The step grades its own paper. FAIL. |
| `INCOMPLETE` | The step is missing a proposer or a ratifier entirely. No second key exists yet. FAIL. |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | CLEAN (every step carries two distinct keys) |
| 1 | NOT CLEAN (at least one same-hand or incomplete step) |
| 2 | usage / input error |

## Requires

- bash 3.2+
- `awk` (GNU or BSD)

No other dependencies; the parser is pure awk.

## Related scripts in this repo

- [gate-keeper](../gate-keeper/) (#18) — refuse to ratify an agent-generated test
  as a passing gate until it clears deterministic checks the authoring agent
  can't fake. `gate-keeper` is the two-key principle applied to test generation;
  `samehand` finds where else in your pipeline it belongs.
- [intent-lint](../intent-lint/) (#20) — refuse an incomplete or out-of-sync
  test-intent manifest before a maintenance agent grounds on it.

## From the newsletter

Companion script for [Bashmatica! Issue #21](https://bashmatica.beehiiv.com).
Hand-raiser keyword: `SAMEHAND`.

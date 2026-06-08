# gate-keeper

Refuse to let an agent-generated test count as a passing gate until it clears
deterministic checks the authoring agent can't fake.

## The problem

An agent explores your app, writes the end-to-end tests, runs them, and reports
back: all green. The suite lands in CI and every signal says the coverage is
real. It isn't, or at least nobody can prove it is, because the same agent that
authored the test decided it passed. The grader and the graded are one process.

There are three ways an agent ships a passing test that proves nothing:

1. It asserts almost nothing, confirming a page rendered without checking it
   rendered correctly.
2. It manipulates state directly (`page.evaluate`, `executeScript`, a DOM
   injection, a stubbed response) so the one assertion it makes is one it
   pre-arranged to pass.
3. It's non-deterministic, passing on the run the agent watched and failing one
   in five on timing it never sat still to notice.

Every one reports green. `gate-keeper` is the second key: a separate process,
with its own logic, that ratifies or refuses the test before it gates CI. The
agent proposes; gate-keeper disposes; the agent never holds both keys.

## Usage

```bash
./gate-keeper.sh --test ./tests/checkout.spec.ts --run "npx playwright test checkout"
./gate-keeper.sh --strict --test <spec> --run "<cmd>"   # an INJECTION flag also refuses
./gate-keeper.sh --density 20 --test <spec> --run "<cmd>"  # stricter floor (1 per 20 lines)
./gate-keeper.sh --no-replay --test <spec>              # static checks only (half a gate)
./gate-keeper.sh --example                              # bundled NOT RATIFIED demo
```

`--run` is the command that runs the test. gate-keeper runs it twice and
compares verdicts, so point it at an isolated runner for a true independent
replay. Drop the whole thing between your generation step and your CI gate.

## The three checks

| Check | What it catches | Verdict |
|-------|-----------------|---------|
| `DENSITY` | A test that asserts (almost) nothing relative to its length: a coverage prop, not a gate | FAIL below the floor |
| `INJECTION` | `page.evaluate` / `executeScript` / DOM mutation / storage overrides / request fulfillment that arrange the conditions of the test's own success | FLAG (FAIL under `--strict`) |
| `REPLAY` | A verdict that doesn't reproduce across two runs: a coin flip, not a gate | FAIL on disagreement |

`INJECTION` flags rather than auto-rejects because not every such call is
illegitimate; the point is to put a human on the exact line that warrants
distrust. The replay check is the one the other integrity scripts in this repo
don't do, and it's the heart of the matter: a test that can't reproduce its own
result hides from every static scan and from the agent's own report.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | RATIFIED (may count as a passing gate; possibly with flags) |
| 1 | NOT RATIFIED (at least one check refused it) |
| 2 | usage / input error |

## Requires

- bash 3.2+
- coreutils (`grep`, `awk`, `sed`) — GNU or BSD

## Related scripts in this repo

- [test-integrity-lint](../test-integrity-lint/) (#7) — state-injection + density scan over a directory.
- [assertion-density-check](../assertion-density-check/) (#8) — density alone.

`gate-keeper` composes the density and injection ideas with the independent
double-replay neither of those performs, as a single ratification gate for one
test at a time.

## From the newsletter

Companion script for
[Bashmatica! Issue #18: Determinism At The Gate, Probabilism In The Workshop](https://bashmatica.beehiiv.com).
Hand-raiser keyword: `GATEKEEPER`.

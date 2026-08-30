# holdstill

Run the same prompt N times through a model CLI, count the distinct outputs,
report the first line where they diverge, and show the distribution of the one
value that matters.

## The problem

Temperature zero is not a lock. In September 2025 Thinking Machines Lab ran
Qwen3-235B 1,000 times on an identical prompt at temperature zero and got 80
distinct completions, with the first divergence as early as token 103. The
sampler is pinned; the serving layer is not. Production inference batches
concurrent requests, batch shape shifts with load, and floating-point reductions
are not associative, so the same prompt lands on different bits depending on who
else was in its batch. The server's traffic is part of your function signature.

The slower version is worse: the model behind a name changes over time. GPT-4
scored 84% on a fixed prime-number task in its March 2023 snapshot and 51% in
June, with no version bump a caller would have seen. "We pinned `gpt-4`" pins a
string, not a distribution of outputs, and the distribution is what the pipeline
consumes. Consistency is not correctness either: a perfectly reproducible pipeline
can return the identical wrong answer every time.

So stop trying to make the model deterministic and engineer the pipeline around a
model that is not. Pin what the provider lets you pin, snapshot what you cannot,
and test the behavior. `holdstill` is the measurement step: it turns "the model
feels flaky" into a number you can put on a dashboard before you decide what to
assert on.

## Usage

```bash
LLM='claude -p' ./holdstill.sh extract.txt                      # 30 runs, default
LLM='llm -m gpt-4o' ./holdstill.sh extract.txt 50               # 50 runs
LLM='claude -p' ./holdstill.sh extract.txt 50 '[0-9]+\.[0-9]{2}' # plus value distribution
./examples/demo.sh                                              # offline, stand-in model
```

`LLM` is any CLI that reads the prompt on stdin and writes the completion to
stdout. The optional third argument is an extended regex that captures the value
that actually matters (a total, a label, a classification); the first match in
each run is tallied.

Sample output:

```
runs:            50
unique outputs:  7
first divergence: 4
--- distribution of the value that matters ---
  47 90.00
   3 100.00
```

Read that as: the phrasing wobbled seven ways, the outputs stopped agreeing on
line 4, and the number you care about was wrong 6% of the time. Assert on the
number, tolerate the phrasing, and put the 6% in front of a human.

## Output fields

| Field | Meaning |
|-------|---------|
| `runs` | how many times the prompt was sent |
| `unique outputs` | distinct complete outputs (byte-for-byte) across all runs |
| `first divergence` | lowest line number at which any run disagrees with run 1, or `none` |
| distribution | count of each captured value, most common first (only with a regex) |

The script has no verdict and always exits 0 once the runs complete; it measures
so that a downstream check (see `goldset`) can decide.

## Requires

- bash 3.2+
- `diff`, `cksum`, `sort`, `uniq`, `grep -E`
- a model CLI on `$PATH` (or set `LLM`)

## Related scripts in this repo

- [goldset](../goldset/) (#27): the regression gate that uses what `holdstill`
  measured, asserting only on the parts that must not move.
- [behavior-canary](../behavior-canary/) (#14): diff an agent's responses to a fixed
  prompt set against a blessed baseline before every deploy.
- [schema-shadow](../schema-shadow/) (#13): catch the structural drift in
  LLM-emitted JSON that a schema validator cannot see.

## From the newsletter

Companion script for
[Bashmatica! #26: Temperature Zero Is Not a Lock](https://www.bashmatica.com/archive/026-temperature-zero-is-not-a-lock/).
Hand-raiser keyword: HOLDSTILL.

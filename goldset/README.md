# goldset

Run a golden set of graded cases through a model and fail the build on the first
regression, so a prompt change or a model bump has a bar to clear before it ships.

## The problem

Your code is frozen until you change it. The model behind it is not. That leaves
you running a component that can change its behavior without a commit, while the
entire safety net, the tests that run when a diff appears, is triggered by diffs.
A model that regresses on its own produces no diff. It slides in under the one
tripwire you have, and the first signal is a support ticket two weeks later
about the invoice step that started grabbing the subtotal.

The fix is not research infrastructure. It is a set of graded cases, drawn from
your own real failures rather than a public benchmark, that a change has to pass
before it is allowed through, the way code has to pass CI before it merges.
Anthropic's guidance is that 20 to 50 tasks pulled from real failures is enough
to start, and that you grade the output, not the path. LangChain's 2025 survey of
more than 1,300 practitioners found only about 52% ran offline evals on a test
set; the rest are shipping on vibes.

`goldset` is the smallest version of that gate. Each case is an input, a grader,
and an expected value; the graders are plain deterministic checks (equals,
contains, regex), so the verdict cannot be flattered. When a case needs a model
as judge, keep that judge advisory and let the deterministic rows block.

## Usage

```bash
LLM='claude -p' ./goldset.sh cases.tsv
LLM='llm -m gpt-4o-2024-11-20' ./goldset.sh cases.tsv
./examples/demo.sh                              # offline, canned stand-in model
```

`cases.tsv` is tab-separated, one case per line, lines starting with `#` ignored:

```
id <TAB> grader <TAB> expected <TAB> prompt
```

Sample run:

```
$ cat cases.tsv
invoice-total   regex     ^90\.00$   Extract only the grand total from: Subtotal 80.00, Tax 10.00, Total 90.00
refund-policy   contains  30 days    What is our stated refund window? Answer from policy only.
promo-applied   equals    72.00      Apply promo SAVE10 to a 80.00 order and give the final total.

$ ./goldset.sh cases.tsv
PASS  invoice-total
PASS  refund-policy
FAIL  promo-applied  expected[equals] 72.00
      got: The final total after the 10% discount is 72.0
---
passed: 2   failed: 1
GOLDSET: regression detected. Change blocked.
```

## Graders and exit codes

| Grader | Passes when |
|--------|-------------|
| `equals` | output equals expected after stripping all whitespace |
| `contains` | output contains the expected string literally |
| `regex` | output matches the expected extended regex |

| Code | Meaning |
|------|---------|
| 0 | every case passed: safe to ship this change |
| 1 | at least one regression: change blocked |
| 2 | unknown grader name in the case file |

Drop it into CI as a required check on any diff that touches a prompt, a model
name, or the extraction code, and run it on a schedule as well, because the
regression you are guarding against arrives without a diff.

## Requires

- bash 3.2+
- `grep`, `tr`, `head`
- a model CLI that reads the prompt on stdin (set `LLM`; default `llm`)

## Related scripts in this repo

- [holdstill](../holdstill/) (#26): measure the run-to-run wobble first, so you
  know which parts of the output are safe to assert on.
- [behavior-canary](../behavior-canary/) (#14): the same idea for tone, refusal
  language and response class, against a baseline instead of an expected value.
- [schema-shadow](../schema-shadow/) (#13): structural drift in LLM JSON that
  passes schema validation.

## From the newsletter

Companion script for
[Bashmatica! #27: Evals Are Regression Tests for a Model That Moves](https://www.bashmatica.com/archive/027-evals-are-regression-tests-for-a-model-that-moves/).
Hand-raiser keyword: GOLDSET.

# intent-lint

Validate a test-intent manifest before a maintenance agent ever reads it, so the
agent is grounded instead of guessing.

## The problem

A maintenance agent looking at a broken test has to answer one question before
it can fix anything: what was this test supposed to verify? A `testscout.config.yaml`
(or any equivalent test-intent manifest) answers that deterministically, every
test declares its intent, its criticality, and the ranked fallback selectors a
healer can climb down to. That is RAG grounding applied to test maintenance:
constrained context instead of open exploration.

But a manifest only grounds the agent if it is complete and if it matches reality
on disk. A test with no declared intent grounds nothing. A config entry pointing
at a file that was deleted grounds nothing. A test file on disk with no entry is
a blind spot the agent will improvise into. `intent-lint` refuses an incomplete
or out-of-sync manifest before the agent trusts it.

## Usage

```bash
./intent-lint.sh --config ./testscout.config.yaml
./intent-lint.sh --config ./testscout.config.yaml --strict   # warnings also refuse
./intent-lint.sh --example                                   # bundled NOT CLEAN demo
```

## The five checks

| Check | What it catches | Verdict |
|-------|-----------------|---------|
| `INTENT` | A test with no declared intent: nothing for the agent to preserve when it fixes the test | FAIL |
| `CRITICALITY` | A test with no criticality: the Planner can't tell a deploy-gating test from a nice-to-have | FAIL |
| `FALLBACKS` | A page-bound test that reaches no ranked fallback chain: the healer has to invent a selector from scratch, the lowest-confidence fix there is | WARN (FAIL under `--strict`) |
| `ORPHAN-CFG` | A config entry whose `file:` was deleted or moved: stale grounding | FAIL |
| `ORPHAN-DISK` | A test file under `test_dir` with no config entry: a test the agent will maintain by guess | WARN (FAIL under `--strict`) |

`FALLBACKS` and `ORPHAN-DISK` warn rather than auto-reject because both are real
gaps that aren't always fatal: a brand-new test legitimately has no fallback
chain yet, and a freshly added spec legitimately hasn't been described yet. The
point is to put them in front of a human before the agent treats the manifest as
complete. `--strict` turns both into refusals for CI.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | CLEAN (the manifest grounds a maintenance agent; possibly with warnings) |
| 1 | NOT CLEAN (at least one check refused it) |
| 2 | usage / input error |

## Requires

- bash 3.2+
- `awk`, `grep`, `find` (GNU or BSD)
- `yq` is optional. If present, it is used only to reject a syntactically broken
  manifest up front; the fact extraction is a pure-awk parser, so there is no
  hard YAML dependency.

## Related scripts in this repo

- [gate-keeper](../gate-keeper/) (#18) — refuse to ratify an agent-generated
  test as a passing gate until it clears deterministic checks the authoring
  agent can't fake. `gate-keeper` guards generation; `intent-lint` guards the
  manifest that grounds maintenance.
- [stale-test-finder](../stale-test-finder/) (#9) — find test files that haven't
  kept pace with their source.
- [blast-radius-guard](../blast-radius-guard/) (#6) — the first gate-keeper in
  the lineage: refuse a diff that reaches past its blast radius.

## From the newsletter

Companion script for
[Bashmatica! Issue #19](https://bashmatica.beehiiv.com).
Hand-raiser keyword: `INTENTLINT`.

# failover-check

Refuse a single-homed LLM provider config before it ships, so a forced model
shutdown can't take your whole product down with it.

## The problem

In June 2026 a U.S. export-control order pulled Anthropic's Fable 5 and Mythos 5
for every customer worldwide, roughly ninety minutes after the letter arrived.
The lesson for builders wasn't about that one model. It was that model access is
a revocable license, not an asset you own, and that provider-level availability
is a different risk from model capability.

The team that had a second provider wired in switched routes and kept serving.
The team whose "fallback" was the same vendor on a different endpoint (the API,
then Bedrock) went down twice, because a provider-level block hits every channel
that vendor runs. `failover-check` reads a routing manifest and refuses a config
that can't survive losing its primary provider.

## Usage

```bash
./failover-check.sh --config ./llm-providers.yaml
./failover-check.sh --config ./llm-providers.yaml --strict   # warnings also refuse
./failover-check.sh --example                                # bundled NOT CLEAN demo
```

The manifest shape it expects:

```yaml
routing:
  primary: anthropic/claude-fable-5
  fallbacks:
    - openai/gpt-5
    - google/gemini-2.5-pro

providers:
  anthropic:
    api_key_env: ANTHROPIC_API_KEY
    models: [claude-fable-5]
  openai:
    api_key_env: OPENAI_API_KEY
    models: [gpt-5]
  google:
    api_key_env: GEMINI_API_KEY
    models: [gemini-2.5-pro]
```

## The five checks

| Check | What it catches | Verdict |
|-------|-----------------|---------|
| `PRIMARY` | No primary route declared: nothing to reason about | FAIL |
| `FAILOVER` | No fallback, or every fallback on the primary's vendor: a provider-level block takes them all at once | FAIL |
| `CREDS` | A routed provider with no block or no `api_key_env`: a fallback you can't authenticate is not a fallback | FAIL |
| `KEY-PRESENT` | An `api_key_env` named in config but unset or empty in the environment: fails over to nothing at runtime | WARN (FAIL under `--strict`) |
| `ORPHAN` | A provider block defined but never routed: usually a typo'd route, or the configured alternative you forgot to wire in | WARN (FAIL under `--strict`) |

`KEY-PRESENT` and `ORPHAN` warn rather than auto-reject because both are real
gaps that aren't always fatal in a dev shell: a key legitimately lives only in
the CI secret store, and an unrouted provider is sometimes staged ahead of use.
The point is to put them in front of a human before the config is treated as
resilient. `--strict` turns both into refusals for CI.

The headline check is `FAILOVER`. A fallback on the same vendor as the primary
is the trap the Fable 5 shutdown exposed: it looks like redundancy and provides
none, because the failure mode that matters isn't one model degrading, it's the
whole vendor going dark across every channel at once.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | CLEAN (the config survives losing its primary provider; possibly with warnings) |
| 1 | NOT CLEAN (at least one check refused it) |
| 2 | usage / input error |

## Requires

- bash 3.2+
- `awk`, `grep` (GNU or BSD)
- `yq` is optional. If present, it is used only to reject a syntactically broken
  manifest up front; the fact extraction is a pure-awk parser, so there is no
  hard YAML dependency.

## Related scripts in this repo

- [env-drift](../env-drift/) (#17) — compare an expected-key manifest against the
  actual environment before an app boots. `env-drift` guards the keys you need;
  `failover-check` guards the route those keys are supposed to make survivable.
- [model-compare](../model-compare/) (#3) — compare model tiers for a task, the
  upstream of routing: pick the model, then make the route resilient.
- [behavior-canary](../behavior-canary/) (#14) — diff a model's responses against
  a baseline before deploy, the capability risk that sits next to this
  availability one.

## From the newsletter

Companion script for
[Bashmatica! Issue #19](https://bashmatica.beehiiv.com).
Hand-raiser keyword: `FAILOVER`.

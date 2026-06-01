# env-drift

Catch environment drift before your app boots into it.

## The problem

Your app expects a set of environment variables. Your `.env.example` documents
them. But the actual environment a deploy boots with drifts: a key gets renamed,
a secret is left blank, a new variable is added in one place and not another.
Nothing errors at boot. The app comes up, reads a blank API key, and fails three
layers down as a 401 or an empty result set that looks like "no data" instead of
"no credentials."

`env-drift` compares an expected-key manifest against the actual environment and
reports exactly what drifted.

## Usage

```bash
./env-drift.sh .env.example .env          # compare two files
./env-drift.sh --from-env .env.example    # compare manifest to the live shell env
./env-drift.sh --strict .env.example .env # EXTRA keys also cause a non-zero exit
./env-drift.sh --example                  # run against the bundled sample
```

The reference can be a `.env.example` (values ignored) or a plain list of bare
`KEY` names. The actual side is either a `.env` file or, with `--from-env`, the
live process environment — drop it into CI right before the build step.

## Drift states

| State | Meaning | Severity |
|-------|---------|----------|
| `MISSING` | Declared in the reference, absent from the actual env | FAIL |
| `EMPTY` | Present in the actual env, but the value is blank | FAIL |
| `EXTRA` | In the actual env, not in the reference | WARN |
| `OK` | Present in both, non-blank value | pass |

`MISSING` and `EMPTY` exit non-zero. `EXTRA` only exits non-zero under `--strict`.

## Requires

- bash 3.2+
- coreutils (`comm`, `sort`, `grep`, `sed`) — GNU or BSD

## From the newsletter

Companion script for [Bashmatica! Issue #17](https://bashmatica.beehiiv.com).
Unrelated to that issue's subject by design — it is a generally useful, widely
overlooked guard against the kind of silent failure that never makes the headlines.

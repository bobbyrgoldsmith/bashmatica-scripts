# schema-shadow

Audit LLM-emitted JSON payloads for the failure modes JSON Schema cannot catch. JSON Schema validates that fields exist with the right types. It does not validate that the values are correct, that array lengths match an expected pattern, or that the model didn't silently drop a populated field one call to the next.

From [Bashmatica! #13](https://bashmatica.beehiiv.com/#).

## The Problem

A pipeline that asks an LLM for JSON gets JSON back. The validator runs, the validator passes, and the orchestrator forwards the payload to the next stage. Every observable signal says the contract held. The contract didn't hold; the validator just couldn't see the part that broke.

JSON Schema validates that `total_amount` is a number. JSON Schema cannot validate that the number is *the right number*. JSONSchemaBench (2025) measured this directly: 16 of 21 tested models scored at or above 96% on Path Recall, Structure Coverage, and Type Safety, while Value Accuracy dropped to 0.69 to 0.83 and Perfect Response Rate (every field correct simultaneously) collapsed to 0.38 to 0.53. The shape passes; the contents are a coin flip.

`schema-shadow` runs the four checks a schema validator skips:

1. **Dropped fields** — the model emits the schema but omits or null-emits a populated field a sibling payload contained.
2. **Type coercion** — string-shaped numbers, ISO-date strings parsed as plain text, booleans-as-strings.
3. **Array drift** — payload array lengths diverging from a baseline beyond a configurable tolerance (catches silent truncation of `line_items[]` and similar patterns).
4. **Field-order drift** — top-level key order differs from a baseline. A soft signal of internal-generation drift, not a hard error.

## Usage

```bash
# Single baseline against a directory of payloads
./schema-shadow.sh --baseline baseline.json ./payloads

# Per-payload baselines (matched by filename)
./schema-shadow.sh --baseline-dir ./baselines ./production-batch

# Tighter array-length tolerance
./schema-shadow.sh --baseline baseline.json --array-tolerance 5 ./payloads

# Skip individual checks
./schema-shadow.sh --baseline baseline.json --no-order-check ./payloads
./schema-shadow.sh --baseline baseline.json --no-type-check ./payloads

# CI mode (silent on success, non-zero exit on findings)
./schema-shadow.sh --ci --baseline baseline.json ./production-batch
```

## Output Format

One finding per line, pipe-delimited:

```
<type>|<file>|<detail>
```

Where `<type>` is one of `dropped`, `type-coerced`, `array-drift`, `order-drift`.

Examples:

```
dropped|payloads/invoice-007.json|line_items.5.unit_price
type-coerced|payloads/invoice-007.json|total_amount|1234.56
array-drift|payloads/invoice-007.json|line_items baseline=20 payload=11 diff=45.00%
order-drift|payloads/invoice-007.json|baseline=[vendor,total] payload=[total,vendor]
```

## Options

| Flag | Description |
|------|-------------|
| `--baseline FILE` | Single baseline payload to compare against. |
| `--baseline-dir DIR` | Directory of baseline payloads, matched by basename. |
| `--array-tolerance PCT` | Array length drift tolerance, default 10%. |
| `--no-type-check` | Skip the type-coercion check. |
| `--no-order-check` | Skip the field-order-drift check. |
| `--no-recursive` | Don't recurse into subdirectories. |
| `--summary` | Print summary statistics only. |
| `--ci`, `--quiet` | Suppress detail output, non-zero exit on findings. |
| `-h`, `--help` | Show help. |

## Environment

| Variable | Effect |
|----------|--------|
| `SCHEMA_SHADOW_SKIP=1` | Skip all checks, exit 0. Useful for emergency CI bypass. |

## Requirements

- Bash 4.0+
- `jq` 1.6+ (`brew install jq` on macOS, `apt install jq` on Debian/Ubuntu)

## Where This Fits

`schema-shadow` is the value-correctness companion to a schema validator, not a replacement for one. The expected pipeline shape is:

1. JSON Schema validation (fails fast on malformed payloads).
2. `schema-shadow` against a baseline (catches drift the schema validator misses).
3. Authoritative-source cross-check for fields originating outside the payload (vendor-name lookup, upstream invoice-number verification, parsed-document layer cross-reference).

Step 3 is the only one that catches all three failure modes documented in Bashmatica! #13. `schema-shadow` is step 2 — it raises the signal floor without requiring an external authoritative source.

## License

MIT — see [repo root](../LICENSE).

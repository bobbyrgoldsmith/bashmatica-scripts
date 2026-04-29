# unit-check

Validate unit-conversion claims against deterministic constants. When LLMs emit shipping manifests, compliance documents, or logistics summaries, they pick a conversion factor each time, and the precision they pick isn't pinned. This script catches both inaccuracies and threshold-crossing errors that route downstream decisions to the wrong tier.

From [Bashmatica! #12](https://bashmatica.beehiiv.com/#).

## The Problem

When you ask an LLM to convert 454 kg to pounds, it might pick the full-precision constant (1 kg = 2.20462262 lb), arriving at 1000.9 lb. The next call, with the same input, might pick the colloquial 1 kg ≈ 2.2 lb, arriving at 998.8 lb. Both look reasonable in isolation. Both are plausible answers to a reviewer skimming a shipping document.

The problem is what happens at a threshold. FedEx Freight applies a heavy-tier surcharge above 1000 lb. The full-precision answer (1000.9 lb) routes to the heavy tier and incurs the surcharge. The colloquial answer (998.8 lb) routes to the standard tier and skips it. Same physical pallet, two different tiers, depending on which conversion factor the model happened to draw on that call.

This kind of variance does not show up in error logs because nothing is technically wrong with either answer. The pipeline that consumes the LLM output has no way to recompute the conversion against a pinned constant before downstream systems act on the value. `unit-check` does that recomputation, flags inaccuracies past a configurable tolerance, and additionally flags any conversion whose imprecision crosses a defined threshold.

## Usage

```bash
# Scan a directory of LLM-generated logistics docs
./unit-check.sh ./shipping-manifests

# Scan specific files
./unit-check.sh manifest.md compliance-report.txt

# FedEx-style tier check (flag any kg-to-lb conversion that
# crosses the 1000-lb threshold)
./unit-check.sh --threshold lb:1000 ./shipping-manifests

# Compliance-grade tolerance (0.05% relative)
./unit-check.sh --strict ./compliance

# Custom relative tolerance
./unit-check.sh --tolerance 1.0 ./logistics

# CI mode (silent on success, non-zero exit on findings)
./unit-check.sh --ci --threshold lb:1000 ./shipping
```

## Patterns Detected

The script recognizes two conversion-claim formats common in generated content:

| Pattern | Example |
|---------|---------|
| `NUM UNIT_A [marker] NUM UNIT_B` | `454 kg = 998.8 lb`, `100 mi equals 160.9 km` |
| `NUM UNIT_A (NUM UNIT_B)` | `454 kg (998.8 lb)`, `100 km (≈ 62.1 mi)` |

Equality markers recognized: `=`, `≈`, `≃`, `equals`, `equal to`, `equivalent to`, `approximately`, `approx.`, `or`, `is`.

## Supported Units

| Domain | Units | Conversion constant |
|--------|-------|---------------------|
| Mass (coarse) | `kg`, `lb` | 1 kg = 2.20462262 lb |
| Mass (fine) | `oz`, `g` | 1 oz = 28.3495231 g |
| Length (long) | `mi`, `km` | 1 mi = 1.609344 km |
| Length (mid) | `ft`, `m` | 1 ft = 0.3048 m |
| Length (short) | `in`, `cm` | 1 in = 2.54 cm |
| Volume | `gal` (US), `L` | 1 gal = 3.785411784 L |
| Temperature | `°F`, `°C` | °F = (°C × 9/5) + 32 |

Both abbreviations and full words are recognized: `kg`, `kilograms`, `kilogram` all match. Temperature requires the degree symbol (`°F`, `°C`) or the full word (`fahrenheit`, `celsius`) to avoid spurious matches on standalone `F` and `C`.

## How It Works

For each text file:

1. **Quick filter** — skip lines that don't contain at least one digit
2. **Pattern match** — try each regex against the line to extract `(source value, source unit, claimed value, claimed unit)`
3. **Recompute** — convert source to target units using full-precision constants via `awk`
4. **Validate**:
   - Compare claimed vs. actual against the configured relative tolerance
   - For each `--threshold UNIT:VALUE` pair, check whether claimed and actual fall on opposite sides of the threshold
5. **Report** — flag the file, line number, source, claimed value, deterministic value, and the percentage delta

## Configuration

| Option / Variable | Default | Description |
|-------------------|---------|-------------|
| `--tolerance PCT` | `0.5` | Relative tolerance percentage |
| `--strict` | off | Sets tolerance to 0.05% (compliance-grade) |
| `--threshold U:V` | none | Flag conversions that cross V in unit U; repeatable |
| `UNIT_CHECK_SKIP=1` | `0` | Skip all checks |

## CI Integration

```yaml
# GitHub Actions — validate generated shipping docs
- name: Unit Check
  run: ./unit-check.sh --ci --threshold lb:1000 ./manifests

# GitLab CI
unit-check:
  script:
    - ./unit-check.sh --ci --strict ./compliance
```

The script exits with code 1 if any inaccuracy or threshold crossing is found, making it suitable as a CI gate for any pipeline that generates conversion-bearing content.

## Example Output

```
==============================================
 UNIT CHECK: Validating conversions
==============================================
  Tolerance: 0.5% (relative)
  Thresholds: lb:1000

  ./manifests/shipment-2026-04-22.md:7  [THRESHOLD]
    Source:  454 kg
    Claimed: 998.8 lb
    Actual:  1000.8987 lb  (delta: 0.2097%)
    > The pallet weighs 454 kg = 998.8 lb. Routes to standard tier.

  ./manifests/shipment-2026-04-22.md:22  [INACCURATE]
    Source:  10 gal
    Claimed: 40 L
    Actual:  37.8541 L  (delta: 5.6689%)
    > We received 10 gal (40 L) of cleaning solvent for distribution.

==============================================
 SUMMARY
==============================================

  Files scanned:           1
  Conversion pairs found:  8
  Inaccuracies:            1
  Threshold crossings:     1
  Files with violations:   1

  Conversions were validated against full-precision constants.
  Inaccuracies exceeded the configured relative tolerance.
  Threshold crossings indicate the claimed value falls on the
  opposite side of a configured threshold from the deterministic
  value, which routes downstream decisions to the wrong tier.
```

The `[THRESHOLD]` row is the FedEx-tier-crossing case: the claimed 998.8 lb is within tolerance of the deterministic 1000.9 lb (0.21% delta), but the two values fall on opposite sides of the 1000-lb threshold, which routes the same pallet to two different surcharge tiers.

## File Types Scanned

When given a directory, the script scans files with these extensions:

`.md`, `.txt`, `.log`, `.html`, `.json`, `.yaml`, `.yml`, `.csv`, `.rst`, `.adoc`, `.org`, `.tex`

Pass files directly to bypass extension filtering. Automatically excludes `.git/`, `node_modules/`, `__pycache__/`, `vendor/`, `dist/`, `.venv/`, `venv/`, `build/`, and `.next/`.

## Limitations

- Negative values (e.g., `-40 °F = -40 °C`) are not currently matched; the regex requires an unsigned numeric token.
- One conversion pair per line (the first pattern match). Lines with multiple conversions are checked against the first match only.
- Volume is US gallons. Imperial gallons (4.54609 L) are not supported.
- The temperature converter expects the degree symbol or full word; bare `F` and `C` are intentionally not matched.
- Multi-step conversions (e.g., kg → lb → oz) are not chained; the script validates one source-to-target conversion per match.

## Requirements

- Bash 4.0+
- Standard Unix tools (awk, find, sort, printf, tr)
- Works on both GNU/Linux and macOS

## License

MIT

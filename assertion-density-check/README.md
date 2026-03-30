# assertion-density-check

Scan test files and flag those with low assertion density: lots of setup, minimal verification.

From [Bashmatica! #8: When the Dashboard Says 94%](https://bashmatica.beehiiv.com/#).

## The Problem

A test that calls a function and asserts nothing inflates coverage identically to a test that calls a function and catches a critical edge case. Coverage tools cannot tell the difference. Your dashboard cannot tell the difference. This script can.

Assertion density (the ratio of assertions to total lines of test code) is a fast proxy for whether your tests are verifying behavior or just executing code. Files with low density are coverage props: they make the number go up without catching defects.

## Usage

```bash
# Scan a test directory
./assertion-density-check.sh ./tests

# Scan the whole project
./assertion-density-check.sh .

# Stricter threshold (1 assertion per 15 lines)
./assertion-density-check.sh --threshold 15 ./tests

# Sort by assertion count (worst first)
./assertion-density-check.sh --sort assertions ./tests

# Summary statistics only
./assertion-density-check.sh --summary ./tests

# CI mode (quiet output, non-zero exit on findings)
./assertion-density-check.sh --quiet ./tests
```

## What It Flags

### Zero-Assertion Files

Test files with no assertions at all. These execute code and verify nothing. They exist solely to inflate coverage metrics.

### Low-Density Files

Test files where the lines-per-assertion ratio exceeds the threshold (default: 1 assertion per 20 lines). A file with 200 lines and 3 assertions has a ratio of 66:1, meaning 97% of the file is setup, teardown, or untested execution.

## Assertion Patterns

The script recognizes assertions from common testing frameworks:

| Framework | Patterns |
|-----------|----------|
| Jest / Vitest / Jasmine | `expect()`, `.toBe()`, `.toEqual()`, `.toContain()`, etc. |
| Mocha + Chai | `.should()`, `.to.*` |
| Python unittest | `self.assert*()`, `self.fail()` |
| Python pytest | `assert`, `pytest.raises()` |
| Go stdlib | `t.Error()`, `t.Fatal()` |
| Go testify | `require.*()`, `assert.*()` |
| Ruby RSpec | `expect().to`, `expect().not_to` |

### Custom Patterns

Create a patterns file with one regex per line:

```
# Custom assertion patterns for our framework
\.mustEqual\(
\.shouldSatisfy\(
expectResult\(
```

Load with `--patterns` or `ASSERT_DENSITY_PATTERNS` env var.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ASSERT_DENSITY_THRESHOLD` | 20 | Max lines-per-assertion ratio before flagging |
| `ASSERT_DENSITY_MIN_LINES` | 10 | Skip files shorter than this |
| `ASSERT_DENSITY_PATTERNS` | (none) | Path to custom assertion patterns file |
| `ASSERT_DENSITY_SKIP` | 0 | Set to 1 to skip all checks |

## CI Integration

```yaml
# GitHub Actions
- name: Assertion Density Check
  run: ./assertion-density-check.sh --quiet ./tests

# GitLab CI
assertion-density:
  script:
    - ./assertion-density-check.sh --quiet ./tests
```

The script exits with code 1 if any files are flagged, making it suitable as a CI gate.

## Test File Detection

Scans for files matching common test naming conventions:

- `*.test.{js,ts,jsx,tsx}`, `*.spec.{js,ts,jsx,tsx}`
- `*_test.{js,ts,py,go}`, `*.test.py`, `*.spec.py`
- `test_*.py`
- `*_spec.rb`, `*_test.rb`

Automatically excludes `node_modules/`, `__pycache__/`, `.git/`, `vendor/`, and `dist/`.

## Example Output

```
==============================================
 NO ASSERTIONS: Coverage props
==============================================

  ./tests/e2e/checkout-flow.spec.ts
    187 lines, 0 assertions

==============================================
 LOW DENSITY: Below threshold (1 per 20 lines)
==============================================

  ./tests/integration/payment.test.ts
    312 lines, 4 assertion(s) (1 per 78 lines)

  ./tests/unit/cart-utils.test.js
    95 lines, 3 assertion(s) (1 per 31 lines)

==============================================
 SUMMARY
==============================================

  Files scanned:        47
  Files flagged:        3
  Zero-assertion files: 1
  Total assertions:     284 across 4,120 lines
  Overall density:      1 assertion per 14 lines
  Threshold:            1 assertion per 20 lines
```

## Requirements

- Bash 4.0+
- grep with `-E` (extended regex) support
- find

## License

MIT

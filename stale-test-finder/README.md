# stale-test-finder

Find test files that haven't kept pace with their source code. When QA capacity shrinks, test maintenance is one of the first things to slip. This script surfaces the drift before production does.

From [Bashmatica! #9: Q1's 52,000 Cuts Didn't Remove Headcount. They Removed the Feedback Loop.](https://bashmatica.beehiiv.com/#).

## The Problem

A test file that hasn't been modified in six months, covering source code that changed last week, is not a passing test. It is an outdated assumption about what that code does. The test may still execute. It may still report green. But it is testing behavior that may no longer exist, missing behavior that was added, and providing false confidence that the code it covers is verified.

This drift happens naturally when teams shrink. Nobody decides to stop maintaining tests. The bandwidth to maintain them disappears along with the headcount, and the dashboard keeps reporting green because passing a stale test is indistinguishable from passing a current one.

## Usage

```bash
# Scan a project directory
./stale-test-finder.sh ./src

# Scan the whole project
./stale-test-finder.sh .

# Shorter staleness window (90 days)
./stale-test-finder.sh --threshold 90 ./src

# Only flag if source changed in the last 30 days (tighter recency)
./stale-test-finder.sh --source-recent 30 ./src

# Summary statistics only
./stale-test-finder.sh --summary ./src

# CI mode (quiet output, non-zero exit on findings)
./stale-test-finder.sh --quiet ./src
```

## How It Works

For each test file found:

1. **Locate the source file** using naming conventions (`.test.ts` -> `.ts`, `_test.py` -> `.py`, `test_utils.py` -> `utils.py`) and directory mapping (`tests/` -> `src/`, `tests/` -> `lib/`)
2. **Check git history** for the last modification date of both the test and its source
3. **Flag the test** if it hasn't been modified in longer than the staleness threshold AND the source file has been modified within the recency window

A test that's 200 days old covering source that's also 200 days old is not flagged: both are stable. A test that's 200 days old covering source that changed 10 days ago is flagged: the test has fallen behind.

## Source File Detection

The script tries multiple strategies to match test files to source files:

| Test File | Source Candidates |
|-----------|-------------------|
| `utils.test.ts` | `utils.ts` (same dir) |
| `utils_test.py` | `utils.py` (same dir) |
| `test_utils.py` | `utils.py` (same dir) |
| `tests/utils.test.ts` | `src/utils.ts`, `lib/utils.ts` |
| `tests/api/handler_test.go` | `api/handler.go` (parent dir) |

If no source file is found, the test is skipped (reported in the summary as "Tests without matched source").

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `STALE_TEST_THRESHOLD` | 180 | Days without modification before a test is considered stale |
| `STALE_TEST_SOURCE_RECENT` | 90 | Days within which source modification counts as "recent" |
| `STALE_TEST_MIN_LINES` | 5 | Skip test files shorter than this |
| `STALE_TEST_SKIP` | 0 | Set to 1 to skip all checks |

## CI Integration

```yaml
# GitHub Actions
- name: Stale Test Check
  run: ./stale-test-finder.sh --quiet ./src

# GitLab CI
stale-tests:
  script:
    - ./stale-test-finder.sh --quiet ./src
```

The script exits with code 1 if stale tests are found, making it suitable as a CI gate or periodic audit job.

## Example Output

```
==============================================
 STALE TESTS: Source changed, tests did not
==============================================

  ./tests/integration/payment.test.ts
    Test last modified: 247 days ago
    Source (./src/integration/payment.ts) last modified: 12 days ago
    Drift: 235 days

  ./tests/unit/cart-utils.spec.js
    Test last modified: 193 days ago
    Source (./src/unit/cart-utils.js) last modified: 41 days ago
    Drift: 152 days

  These test files have not been updated to reflect changes in the
  source code they cover. The test may still pass, but it is testing
  assumptions about code that no longer matches those assumptions.

==============================================
 SUMMARY
==============================================

  Test files scanned:         34
  Stale tests found:          2
  Tests without matched source: 5 (skipped)
  Tests current:              27
  Staleness threshold:        180 days
  Source recency window:       90 days
```

## Test File Detection

Scans for files matching common test naming conventions:

- `*.test.{js,ts,jsx,tsx}`, `*.spec.{js,ts,jsx,tsx}`
- `*_test.{js,ts,py,go}`, `*.test.py`, `*.spec.py`
- `test_*.py`
- `*_test.rb`, `*_spec.rb`

Automatically excludes `node_modules/`, `__pycache__/`, `.git/`, `vendor/`, `dist/`, `.venv/`, `venv/`, `build/`, and `.next/`.

## Requirements

- Bash 4.0+
- Git (uses `git log` for modification timestamps)
- Standard Unix tools (find, sed, wc, sort, date)

## License

MIT

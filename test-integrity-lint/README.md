# test-integrity-lint

Scan test files for patterns that indicate state manipulation outside proper test fixtures, and check assertion density.

From [Bashmatica! #7: The Trust Decay Problem](https://bashmatica.beehiiv.com/#).

## The Problem

AI agents building test suites will sometimes manipulate browser state directly (via `page.evaluate()`, `executeScript()`, DOM injection) to force a passing result rather than reporting a legitimate failure. The agent optimizes for the metric (green tests) instead of the goal (catching bugs).

This script flags two categories of risk:

1. **State injection** — Direct DOM manipulation, storage overrides, cookie injection, and fetch interception in test files that bypass the application's own state management.
2. **Low assertion density** — Test files with extensive setup but minimal actual verification, which may confirm structure without catching defects.

## Usage

```bash
# Scan a test directory
./test-integrity-lint.sh ./tests

# Scan the whole project
./test-integrity-lint.sh .

# Only check state injection patterns
./test-integrity-lint.sh --injection-only ./tests

# Only check assertion density (custom threshold)
./test-integrity-lint.sh --assertions-only --threshold 5 ./tests

# CI mode (quiet output, non-zero exit on findings)
./test-integrity-lint.sh --quiet ./tests

# List all active patterns
./test-integrity-lint.sh --list

# Add custom patterns
./test-integrity-lint.sh --patterns my-patterns.txt ./tests
```

## What It Catches

### State Injection Patterns

| Category | Examples |
|----------|----------|
| Playwright/Puppeteer evaluation | `page.evaluate()`, `page.addScriptTag()` |
| Selenium script execution | `executeScript()`, `execute_script()` |
| Direct DOM mutation | `document.querySelector().innerHTML = ...` |
| Storage manipulation | `localStorage.setItem()`, `sessionStorage.clear()` |
| Cookie injection | `document.cookie = ...` |
| Global state override | `window.someVar = ...` |
| Request interception | `page.route(...fulfill)`, `cy.intercept(...reply)` |

### Assertion Density

Flags test files with fewer than N assertions (default: 3) and more than 10 lines. A test file with 200 lines of setup and two assertions is a confidence artifact, not a quality gate.

## Custom Patterns

Create a patterns file with one regex per line:

```
# My custom patterns
\.overridePermissions\(
page\.setGeolocation\(
page\.setExtraHTTPHeaders\(
```

Load with `--patterns` or `TEST_LINT_PATTERNS` env var.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `TEST_LINT_THRESHOLD` | 3 | Minimum assertions per test file |
| `TEST_LINT_PATTERNS` | (none) | Path to custom patterns file |
| `TEST_LINT_SKIP` | 0 | Set to 1 to skip all checks |

## CI Integration

Add to your CI pipeline:

```yaml
# GitHub Actions
- name: Test Integrity Lint
  run: ./test-integrity-lint.sh --quiet ./tests

# GitLab CI
test-lint:
  script:
    - ./test-integrity-lint.sh --quiet ./tests
```

## Test File Detection

The script scans for files matching common test naming conventions:

- `*.test.{js,ts,jsx,tsx}`, `*.spec.{js,ts,jsx,tsx}`
- `*_test.{js,ts,py,go}`, `*.test.py`, `*.spec.py`
- `test_*.py`

Automatically excludes `node_modules/`, `__pycache__/`, `.git/`, and `vendor/`.

## Important Notes

Not every `page.evaluate()` is a problem. Legitimate uses include setting up authentication tokens, configuring test-specific feature flags through the application's own API, or reading computed styles for visual regression tests. The script flags patterns for review; the judgment call is yours.

The goal is to ensure that test execution is atomic, follows the AAA pattern (Arrange-Act-Assert), and that the agent's objective is catching bugs rather than passing tests.

## Requirements

- Bash 4.0+
- grep with `-E` (extended regex) support
- find

## License

MIT

# mutant-check

Lightweight mutation testing for any language and test runner. Applies operator mutations to a source file one at a time, runs your tests after each, and reports which mutations your tests caught vs. missed.

From [Bashmatica! #10: 15,000 Artificial Bugs. Facebook's Tests Caught Less Than Half.](https://bashmatica.beehiiv.com/#).

## The Problem

A test suite that reports 94% coverage and passes every run can still miss more than half of the bugs in the code it covers. Facebook demonstrated this in 2021 when they injected 15,000 artificial faults into a subset of their Java codebase and found that their full battery of unit, integration, and system tests allowed the majority to survive undetected.

The gap between "tests execute this code" and "tests verify this code behaves correctly" is invisible to coverage metrics. Mutation testing closes that gap by asking a direct question: if I change one thing in the source, does any test notice?

Production-grade mutation testing tools like PIT, StrykerJS, and mutmut handle this at scale. This script is a zero-dependency educational alternative that demonstrates the concept against any language and test runner, using nothing beyond bash and your existing test command.

## Usage

```bash
# Python project
./mutant-check.sh --source src/pricing.py --test "pytest tests/ -q"

# JavaScript project
./mutant-check.sh --source src/utils.js --test "npm test"

# Go project
./mutant-check.sh --source handler.go --test "go test ./..."

# Rust project
./mutant-check.sh --source src/lib.rs --test "cargo test --quiet"

# With a longer timeout per mutation (default: 30s)
./mutant-check.sh --source app.py --test "pytest" --timeout 60

# CI mode (quiet output, non-zero exit on survivors)
./mutant-check.sh --quiet --source src/pricing.py --test "pytest"
```

## How It Works

1. **Baseline check** verifies that your test command passes on the unmodified source file. If tests are already failing, the script exits before mutating anything.
2. **For each mutation operator**, the script scans the source file line by line, looking for the target pattern.
3. **When a match is found**, the script creates a mutant by replacing the operator, runs your test command, then immediately restores the original file.
4. **Results are classified** as KILLED (tests failed, mutation detected), SURVIVED (tests passed, blind spot found), or TIMEOUT (tests hung, treated separately).

The original source file is never permanently modified. A `.mutant` backup is created before each mutation and used to restore after each test run.

## Mutation Operators

| Category | Original | Mutant | What it tests |
|----------|----------|--------|---------------|
| Equality | `==` | `!=` | Do tests verify equality conditions? |
| Equality | `!=` | `==` | Do tests verify inequality conditions? |
| Strict equality | `===` | `!==` | Do tests verify strict type checks? |
| Strict equality | `!==` | `===` | Do tests verify strict inequality? |
| Boundary | `>` | `>=` | Do tests cover boundary values? |
| Boundary | `<` | `<=` | Do tests cover boundary values? |
| Boundary | `>=` | `>` | Do tests cover the equals case? |
| Boundary | `<=` | `<` | Do tests cover the equals case? |
| Logical | `&&` | `\|\|` | Do tests verify both conditions matter? |
| Logical | `\|\|` | `&&` | Do tests verify either condition suffices? |
| Increment | `++` | `--` | Do tests verify direction of change? |
| Increment | `--` | `++` | Do tests verify direction of change? |
| Boolean | `true` | `false` | Do tests verify true/false paths? |
| Boolean | `false` | `true` | Do tests verify true/false paths? |
| Return | `return ` | `return !` | Do tests verify return value correctness? |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MUTANT_CHECK_TIMEOUT` | `30` | Max seconds per test run before classifying as TIMEOUT |
| `MUTANT_CHECK_SKIP` | `0` | Set to `1` to skip all checks |

## CI Integration

```yaml
# GitHub Actions
- name: Mutation Check
  run: ./mutant-check.sh --quiet --source src/pricing.py --test "pytest tests/ -q"

# GitLab CI
mutation-check:
  script:
    - ./mutant-check.sh --quiet --source src/pricing.py --test "pytest tests/ -q"
```

The script exits with code 1 if surviving mutants are found, making it suitable as a CI gate for critical source files.

## Example Output

```
==============================================
 MUTANT-CHECK: Mutation testing src/pricing.py
==============================================

  Test command: pytest tests/ -q
  Timeout: 30s per mutation

  Verifying tests pass on unmodified source...
  Baseline: PASS

  Running mutations...

  KILLED   L12   equality → inequality
  KILLED   L12   inequality → equality
  SURVIVED L18   greater-than → greater-or-equal
           > if discount > 0:
  KILLED   L18   boolean true → false
  KILLED   L24   equality → inequality

==============================================
 SUMMARY
==============================================

  Source file:      src/pricing.py
  Mutants generated: 5
  Killed (caught):   4
  Survived (missed): 1
  Mutation score:    80%

  Surviving mutants indicate test blind spots: the source
  code changed, but no test noticed. These are gaps that
  a coverage report would never surface.
```

## Limitations

- **Educational, not production-grade.** For real mutation testing, use PIT (Java), StrykerJS (JS/TS), mutmut (Python), or cargo-mutants (Rust).
- **One file at a time.** This script mutates a single source file. Production tools operate across entire modules or packages.
- **Text-level mutations.** Operators inside string literals, comments, or variable names may be matched. Production tools parse the AST to avoid false matches.
- **Sequential execution.** Each mutation runs the full test command. Production tools use per-test coverage mapping to run only relevant tests.
- **No equivalent mutant detection.** Some mutations produce functionally identical code. Production tools filter these out; this script does not.

## Requirements

- Bash 4.0+
- Standard Unix tools (sed, grep, cp, rm)
- `timeout` (GNU coreutils) or `gtimeout` (macOS via Homebrew coreutils) for per-mutation timeouts. Falls back to no timeout if neither is available.

## License

MIT

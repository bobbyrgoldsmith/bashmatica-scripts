# weekday-audit

Scan text files for mismatches between day-of-week names and calendar dates. When LLMs generate reports, briefs, and documentation, they get the dates right and the day names wrong. This script catches it.

From [Bashmatica! #10](https://bashmatica.beehiiv.com/#).

## The Problem

When you ask an LLM to generate a daily brief, a changelog header, or a scheduling summary, it will format the date correctly — April 9, 2026 — and then confidently attach the wrong day of the week. Not because the model can't parse dates. Because it doesn't have a calendar. It's pattern-matching from training data, and for dates outside that window, the pattern breaks.

This is the kind of error nobody checks for. The format looks right. The date is right. The day name is plausible. Wednesday is a perfectly reasonable thing for April 9 to be — unless you know it's actually a Thursday. And if your automation pipeline uses that day name to determine which actions to take (Monday planning, Tuesday publishing, Friday reviews), a one-day drift means every downstream decision is keyed to the wrong schedule.

The fix at the source is straightforward: compute the day name in shell and hand it to the model. But if you're auditing existing content — or validating output from a system you don't control — you need a way to check what's already been written.

## Usage

```bash
# Scan a directory of LLM-generated reports
./weekday-audit.sh ./reports

# Scan specific files
./weekday-audit.sh changelog.md meeting-notes.md daily-brief.md

# Scan without recursing into subdirectories
./weekday-audit.sh --no-recursive ./docs

# Summary statistics only
./weekday-audit.sh --summary ./reports

# CI mode (quiet output, non-zero exit on findings)
./weekday-audit.sh --quiet ./docs
```

## Patterns Detected

The script recognizes four date-day formats commonly found in generated content:

| Pattern | Example |
|---------|---------|
| Day, Month DD, YYYY | `Wednesday, April 9, 2026` |
| Month DD, YYYY (Day) | `April 9, 2026 (Wednesday)` |
| YYYY-MM-DD (Day) | `2026-04-09 (Wednesday)` |
| Day, YYYY-MM-DD | `Wednesday, 2026-04-09` |

Both full names (`Wednesday`, `April`) and abbreviations (`Wed`, `Apr`) are recognized. Commas between components are optional.

## How It Works

For each text file:

1. **Quick filter** — skip lines that don't contain a day name substring
2. **Pattern match** — try each regex pattern against the line to extract the claimed day name and the calendar date
3. **Validate** — compute the actual weekday for that date using your system's `date` command and compare
4. **Report** — if the claimed day doesn't match the actual day, flag it with the file, line number, and correction

The script detects whether you're running GNU `date` (Linux) or BSD `date` (macOS) and adapts the date computation accordingly.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `WEEKDAY_AUDIT_SKIP` | `0` | Set to `1` to skip all checks |

## CI Integration

```yaml
# GitHub Actions — validate generated docs
- name: Weekday Audit
  run: ./weekday-audit.sh --quiet ./docs ./reports

# GitLab CI
weekday-check:
  script:
    - ./weekday-audit.sh --quiet ./docs
```

The script exits with code 1 if mismatches are found, making it suitable as a CI gate for any pipeline that generates date-stamped content.

## Example Output

```
==============================================
 WEEKDAY AUDIT: Checking date-day consistency
==============================================

  ./reports/daily-brief-2026-04-09.md:1
    Claims: Wednesday   Actual: Thursday    Date: 2026-04-09
    > # Daily Brief — Wednesday, April 9, 2026

  ./reports/daily-brief-2026-04-09.md:54
    Claims: Wednesday   Actual: Thursday    Date: 2026-04-09
    > ## Today's Content Schedule (Wednesday — Publish Day)

  ./changelog.md:12
    Claims: Friday      Actual: Saturday    Date: 2026-03-14
    > ## v2.1.0 — Friday, March 14, 2026

==============================================
 SUMMARY
==============================================

  Files scanned:          14
  Date-day pairs checked: 23
  Mismatches found:       3
  Files with mismatches:  2

  Day names were validated against your system's calendar.
  Mismatches indicate the text claims a different weekday
  than the date actually falls on.
```

## File Types Scanned

When given a directory, the script scans files with these extensions:

`.md`, `.txt`, `.log`, `.html`, `.json`, `.yaml`, `.yml`, `.csv`, `.rst`, `.adoc`, `.org`, `.tex`

Pass files directly to bypass extension filtering. Automatically excludes `.git/`, `node_modules/`, `__pycache__/`, `vendor/`, `dist/`, `.venv/`, `venv/`, `build/`, and `.next/`.

## Limitations

- Detects one date-day pair per line (the first pattern match). Lines with multiple dates are checked against the first match only.
- Does not detect day names separated from their dates by multiple lines (e.g., "Wednesday" on one line and "April 9, 2026" on the next).
- Month-Day-Year without a day name (e.g., "April 9, 2026" alone) is not flagged — there's nothing to validate without a claimed day name.

## Requirements

- Bash 4.0+
- Standard Unix tools (date, find, sort, printf, tr)
- Works on both GNU/Linux and macOS (auto-detects `date` flavor)

## License

MIT

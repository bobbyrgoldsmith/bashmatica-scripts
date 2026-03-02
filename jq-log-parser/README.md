# jq-log-parser

Structured JSON log parsing utilities using `jq`. Extracts error counts, groups by service or time window, and identifies slow requests from JSONL-formatted application logs.

From [Bashmatica! #4: When "AI-Native" Means "40% Fewer of You"](https://bashmatica.beehiiv.com/#).

## Quick Start

The one-liner from the newsletter:

```bash
jq -r 'select(.level == "error") | .service' /var/log/app/*.json \
  | sort | uniq -c | sort -rn | head -20
```

The full script in this directory wraps that pattern (and several others) into a reusable tool.

## Usage

```bash
chmod +x jq_log_parser.sh

# Count errors by service
./jq_log_parser.sh errors-by-service /var/log/app/app.json

# Count errors by hour
./jq_log_parser.sh errors-by-time /var/log/app/app.json

# Summary with service, count, latest timestamp, and sample message
./jq_log_parser.sh error-summary /var/log/app/app.json

# Find requests slower than 500ms
./jq_log_parser.sh slow-requests -t 500 /var/log/app/app.json

# Pipe from stdin
cat /var/log/app/*.json | ./jq_log_parser.sh errors-by-service -

# Limit results
./jq_log_parser.sh errors-by-service -n 5 /var/log/app/app.json

# Filter by level (default: error)
./jq_log_parser.sh errors-by-service -l warn /var/log/app/app.json
```

## Commands

| Command | Description |
|---------|-------------|
| `errors-by-service` | Count log entries at specified level, grouped by `.service` |
| `errors-by-time` | Count log entries at specified level, grouped by hour |
| `error-summary` | JSON output with service, count, latest timestamp, and sample message |
| `slow-requests` | Find requests exceeding a duration threshold (TSV output) |

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `-n, --limit` | 20 | Maximum number of results |
| `-l, --level` | error | Log level to filter on |
| `-t, --threshold` | 1000 | Duration threshold in ms (slow-requests only) |

## Expected Log Format

The script expects JSONL (one JSON object per line) with these common fields:

```json
{
  "level": "error",
  "service": "payment-api",
  "timestamp": "2026-03-02T14:30:00Z",
  "message": "Connection timeout to downstream service",
  "duration": 1250
}
```

Not all fields are required for every command. `errors-by-service` only needs `.level` and `.service`; `slow-requests` needs `.duration`.

## Pairing with LLM Analysis

Pipe output through the [llm-sanitizer](../llm-sanitizer/) before sending to any cloud LLM:

```bash
./jq_log_parser.sh error-summary /var/log/app/app.json \
  | ../llm-sanitizer/sanitize.sh \
  | llm_command "Analyze these error patterns and suggest investigation priorities"
```

## Requirements

- `jq` 1.6+
- Bash 4.0+
- Standard coreutils (sort, uniq, head, sed)

## License

MIT License. See [LICENSE](../LICENSE) for details.

# llm-sanitizer

Strip secrets from logs before sending to LLMs.

Part of [bashmatica-scripts](https://github.com/bobbyrgoldsmith/bashmatica-scripts) by NodeBridge Automation Solutions.

## The Problem

Every time you pipe logs to an LLM for analysis, you risk sending secrets to a third party. Production logs are littered with:

- Database connection strings with embedded passwords
- API keys in error messages
- Bearer tokens and session identifiers
- Internal IP addresses revealing infrastructure topology
- Customer email addresses

This script catches the obvious leaks before they leave your network.

## Quick Start

```bash
# Make executable
chmod +x sanitize.sh

# Basic usage
cat /var/log/app/error.log | ./sanitize.sh

# Pipe to your LLM of choice
cat error.log | ./sanitize.sh | llm "analyze these errors"

# With Claude CLI
kubectl logs my-pod | ./sanitize.sh | claude "what's causing these failures?"
```

## Installation

### Option 1: Add to PATH

```bash
# Clone the repo
git clone https://github.com/bobbyrgoldsmith/bashmatica-scripts.git
cd bashmatica-scripts/llm-sanitizer

# Make executable and add to PATH
chmod +x sanitize.sh
sudo ln -s "$(pwd)/sanitize.sh" /usr/local/bin/llm-sanitize
```

### Option 2: Shell Function

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# Minimal version for quick use
sanitize_for_llm() {
    sed -E \
        -e 's/([Pp]assword[=:]["'"'"']?)[^"'"'"'\s]+/\1[REDACTED]/g' \
        -e 's/([Aa]pi[_-]?[Kk]ey[=:]["'"'"']?)[A-Za-z0-9_-]{16,}/\1[REDACTED]/g' \
        -e 's/([Tt]oken[=:]["'"'"']?)[A-Za-z0-9_.-]{20,}/\1[REDACTED]/g' \
        -e 's/([Ss]ecret[=:]["'"'"']?)[^"'"'"'\s]+/\1[REDACTED]/g' \
        -e 's/Bearer [A-Za-z0-9_.-]+/Bearer [REDACTED]/g' \
        -e 's/AKIA[0-9A-Z]{16}/[AWS_ACCESS_KEY]/g' \
        -e 's/ghp_[A-Za-z0-9]{36}/[GITHUB_PAT]/g' \
        -e 's/sk_live_[A-Za-z0-9]{24,}/[STRIPE_SECRET_KEY]/g'
}

# Usage: cat logs.txt | sanitize_for_llm | llm "analyze"
```

## What It Catches

### Cloud Provider Credentials

| Provider | Pattern | Replacement |
|----------|---------|-------------|
| AWS | `AKIA...` (access keys) | `[AWS_ACCESS_KEY]` |
| AWS | Secret access keys | `[REDACTED]` |
| GCP | `AIza...` (API keys) | `[GCP_API_KEY]` |
| GCP | `ya29...` (access tokens) | `[GCP_ACCESS_TOKEN]` |
| Azure | Storage connection strings | `[AZURE_STORAGE_CONNECTION]` |

### Code Hosting

| Provider | Pattern | Replacement |
|----------|---------|-------------|
| GitHub | `ghp_...` (PATs) | `[GITHUB_PAT]` |
| GitHub | `gho_...` (OAuth) | `[GITHUB_OAUTH]` |
| GitHub | Server/refresh tokens | `[GITHUB_*_TOKEN]` |

### Payment Processors

| Provider | Pattern | Replacement |
|----------|---------|-------------|
| Stripe | `sk_live_...` | `[STRIPE_SECRET_KEY]` |
| Stripe | `sk_test_...` | `[STRIPE_TEST_KEY]` |
| Stripe | `rk_live_...` | `[STRIPE_RESTRICTED_KEY]` |

### Communication Platforms

| Provider | Pattern | Replacement |
|----------|---------|-------------|
| Slack | `xoxb-...`, `xoxp-...` | `[SLACK_TOKEN]` |
| Slack | Webhook URLs | `[SLACK_WEBHOOK]` |

### Database Connection Strings

| Database | Example | Result |
|----------|---------|--------|
| MongoDB | `mongodb://user:pass@host` | `mongodb://[USER]:[REDACTED]@host` |
| PostgreSQL | `postgres://user:pass@host` | `postgres://[USER]:[REDACTED]@host` |
| MySQL | `mysql://user:pass@host` | `mysql://[USER]:[REDACTED]@host` |
| Redis | `redis://user:pass@host` | `redis://[USER]:[REDACTED]@host` |

### Other Sensitive Data

| Type | Handling |
|------|----------|
| Bearer tokens | `Bearer [REDACTED]` |
| Basic auth | `Basic [REDACTED]` |
| JWTs | Signature portion redacted |
| Private keys | `[PRIVATE_KEY_REDACTED]` |
| Internal IPs | `10.x.x.x`, `192.168.x.x` → `[INTERNAL_IP]` |
| Email addresses | Partially masked: `j***@example.com` |
| Generic password/secret/token fields | `[REDACTED]` |

## Options

```
-v, --verbose    Show redaction count to stderr
-c, --config     Use custom patterns file
-h, --help       Show help message
--version        Show version
```

### Verbose Mode

See what was caught:

```bash
$ cat error.log | ./sanitize.sh -v
[llm-sanitizer] Redacted 7 potential secrets
<sanitized output...>
```

### Custom Patterns

Create a patterns file (one regex per line):

```bash
# my-patterns.txt
# Internal hostnames
prod-db-[0-9]+\.internal\.company\.com
staging-[a-z]+-[0-9]+\.internal

# Custom token format
MYAPP_[A-Z0-9]{32}

# Internal service URLs
https?://[a-z]+-service\.internal:[0-9]+
```

Use it:

```bash
cat logs.txt | ./sanitize.sh -c my-patterns.txt
```

## Example

### Before

```
2024-01-15 14:32:01 ERROR PaymentService: Failed to process payment
  stripe_key: sk_live_XXXXXXXXXXXX
  customer_email: john.doe@example.com
  error: Connection to postgres://admin:SuperSecret123@prod-db.internal:5432/payments failed
  trace_id: 550e8400-e29b-41d4-a716-446655440000

2024-01-15 14:32:02 ERROR AuthService: Token refresh failed
  Authorization: Bearer eyXXXXXXXXXXXXXXXXXX.eyXXXXXXXXXXXXXXX.XXXXXXXXXXXXXXXX
  github_token: ghp_EXAMPLE_TOKEN_REPLACE_ME_1234567890
  AWS_ACCESS_KEY_ID: AKIA_EXAMPLE_KEY_HERE
```

### After

```
2024-01-15 14:32:01 ERROR PaymentService: Failed to process payment
  stripe_key: [STRIPE_SECRET_KEY]
  customer_email: j***@example.com
  error: Connection to postgres://[USER]:[REDACTED]@prod-db.internal:5432/payments failed
  trace_id: [UUID]

2024-01-15 14:32:02 ERROR AuthService: Token refresh failed
  Authorization: Bearer [REDACTED]
  github_token: [GITHUB_PAT]
  AWS_ACCESS_KEY_ID: [AWS_ACCESS_KEY]
```

## Integration Examples

### With Claude CLI

```bash
# Analyze errors
cat /var/log/nginx/error.log | ./sanitize.sh | claude "summarize the errors in the last hour"

# Debug a specific issue
kubectl logs deployment/api --since=1h | ./sanitize.sh | claude "why are requests timing out?"
```

### With Ollama (Local)

For sensitive logs that can't leave your infrastructure:

```bash
# Set up alias
alias llm-local='ollama run llama3'

# Sanitize anyway (defense in depth)
cat sensitive.log | ./sanitize.sh | llm-local "analyze these errors"
```

### In CI/CD Pipelines

```yaml
# GitHub Actions example
- name: Analyze test failures
  if: failure()
  run: |
    cat test-output.log | ./scripts/sanitize.sh > sanitized.log
    # Send sanitized logs to analysis service
```

### Shell Alias

```bash
# Add to ~/.bashrc or ~/.zshrc
alias llm-safe='sanitize.sh | llm'

# Usage
cat error.log | llm-safe "what's wrong here?"
```

## Limitations

This tool catches common patterns but isn't foolproof. It won't catch:

- Secrets in non-standard formats
- Encoded or encrypted secrets (base64 that isn't a known token format)
- Secrets in binary data
- Context that reveals secrets indirectly

**Always review output before sending to third parties.** The goal is reducing risk, not eliminating it.

## Contributing

Found a pattern we're missing? Open a PR or issue at [bashmatica-scripts](https://github.com/bobbyrgoldsmith/bashmatica-scripts).

Common additions:

- New SaaS provider token formats
- Industry-specific patterns (healthcare, finance)
- Regional compliance requirements

## License

MIT License. See [LICENSE](../LICENSE).

---

Part of the [Bashmatica!](https://bashmatica.beehiiv.com) newsletter by Bobby R. Goldsmith.

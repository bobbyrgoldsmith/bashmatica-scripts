# SSL Certificate Auto-Check & Renew — Full Explanation

A deep-dive into how `ssl-check-renew.sh` works, why each piece exists, and how to adapt it for your environment.

## Why This Script Exists

SSL certificate expiration is one of the most preventable causes of production outages. Major companies — including Microsoft, Spotify, and Equifax — have suffered public incidents from expired certs. Let's Encrypt made free certificates ubiquitous, but their 90-day lifespan means renewal automation isn't optional.

The built-in `certbot renew` command handles renewal, but it assumes:
- The certbot systemd timer is installed and running
- The original certificate was issued via certbot
- Nothing has changed in your DNS or web server config

This script adds a **verify-first** approach: check the live certificate over the network (the same way a browser would), then act based on what's actually served — not what certbot thinks is installed.

## Script Walkthrough

### Strict Mode

```bash
set -euo pipefail
```

Three safety flags in one line:
- `set -e` — exit immediately if any command fails (non-zero exit code)
- `set -u` — treat unset variables as errors instead of silently expanding to empty strings
- `set -o pipefail` — a pipeline fails if *any* command in it fails, not just the last one

This matters here because a silent failure in the openssl pipeline could lead to renewing a cert that doesn't need it, or worse, skipping a renewal that does.

### Argument Parsing

```bash
DOMAIN="${1:?Usage: $0 <domain> [threshold_days] [email]}"
THRESHOLD_DAYS="${2:-30}"
EMAIL="${3:-}"
```

Bash parameter expansion handles all three patterns:
- `${1:?message}` — if `$1` is unset or empty, print the message to stderr and exit. This is the simplest way to make an argument required without writing a full arg parser.
- `${2:-30}` — use `$2` if set, otherwise default to `30`.
- `${3:-}` — use `$3` if set, otherwise empty string. The `:-` with no default is intentional: it prevents `set -u` from triggering on an optional argument.

### Logging

```bash
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}
```

Dual output: stdout (for interactive use and cron email capture) and a persistent log file. The `2>/dev/null || true` ensures the script doesn't crash if the log file isn't writable (e.g., running without sudo). The `$*` expands all function arguments as a single string, which is the right choice here since we're building a log message, not iterating over args.

### Certificate Inspection

```bash
get_cert_expiry() {
  local expiry
  expiry=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | sed 's/notAfter=//')
  ...
}
```

This is the core of the script. Here's what each piece does:

1. **`echo |`** — sends an empty line to stdin so `s_client` doesn't hang waiting for input.
2. **`openssl s_client -servername "$DOMAIN" -connect "$DOMAIN:443"`** — opens a TLS connection. The `-servername` flag sends the SNI (Server Name Indication) header, which is critical on servers hosting multiple domains behind a single IP. Without it, you might get the wrong certificate.
3. **`openssl x509 -noout -enddate`** — parses the certificate from the connection and extracts only the expiry date. `-noout` suppresses the full cert dump.
4. **`sed 's/notAfter=//'`** — strips the field label, leaving just the date string like `Mar 15 12:00:00 2026 GMT`.

The `2>/dev/null` on both openssl commands suppresses connection diagnostics and warnings that would pollute the output.

### Cross-Platform Date Conversion

```bash
to_epoch() {
  local datestr="$1"
  if date --version &>/dev/null; then
    date -d "$datestr" +%s
  else
    date -j -f "%b %d %H:%M:%S %Y %Z" "$datestr" +%s
  fi
}
```

This is necessary because GNU `date` (Linux) and BSD `date` (macOS) have incompatible syntax for parsing date strings:

| Platform | Parse a date string | Flag |
|----------|-------------------|------|
| GNU/Linux | `date -d "Mar 15 12:00:00 2026 GMT" +%s` | `-d` |
| macOS/BSD | `date -j -f "%b %d %H:%M:%S %Y %Z" "Mar 15 12:00:00 2026 GMT" +%s` | `-j -f` |

The detection trick: GNU `date` supports `--version`, BSD `date` does not. If `date --version` succeeds, we're on GNU. The `&>/dev/null` suppresses both stdout and stderr so the version output doesn't leak.

The format string `%b %d %H:%M:%S %Y %Z` matches the exact output format of openssl's `notAfter` field:
- `%b` — abbreviated month name (Mar)
- `%d` — day of month (15)
- `%H:%M:%S` — time (12:00:00)
- `%Y` — four-digit year (2026)
- `%Z` — timezone abbreviation (GMT)

### Days-Remaining Calculation

```bash
expiry_epoch=$(to_epoch "$expiry_str")
now_epoch=$(date +%s)
days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
```

Epoch seconds make date math trivial: subtract, divide by 86400 (seconds in a day). Integer division in bash truncates, so 29.9 days becomes 29 — which is conservative (it'll renew slightly early rather than late). This is the right behavior for cert renewal.

### Renewal via Certbot

```bash
$CERTBOT_BIN certonly \
  --non-interactive \
  --agree-tos \
  $email_flag \
  --preferred-challenges http \
  -d "$DOMAIN" \
  --keep-until-expiring \
  --renew-with-new-domains
```

Key flags explained:

| Flag | Purpose |
|------|---------|
| `certonly` | Only obtain the cert; don't modify web server config |
| `--non-interactive` | Never prompt for input (required for cron/automation) |
| `--agree-tos` | Accept Let's Encrypt Terms of Service |
| `--preferred-challenges http` | Use HTTP-01 challenge (place a file in `.well-known/acme-challenge/`) |
| `--keep-until-expiring` | Don't re-issue if the current cert is still valid — respects rate limits |
| `--renew-with-new-domains` | Allow renewal even if the domain list has changed |

The `--keep-until-expiring` flag is an important safety net. Even if this script runs when the cert has 60 days left (above the threshold), certbot won't wastefully re-issue. Let's Encrypt enforces rate limits (5 duplicate certs per week), and this flag prevents burning through them.

### Decision Logic

```bash
if (( days_left <= 0 )); then
  renew_cert           # Already expired
elif (( days_left <= THRESHOLD_DAYS )); then
  renew_cert           # Expiring soon
else
  log "OK"             # Still valid
fi
```

Three states, each logged. The `(( ))` arithmetic context is cleaner than `[ $days_left -le 0 ]` and handles negative numbers correctly (which can happen if the cert expired days ago).

The fallback case at the top of `main()` handles a fourth state: **no cert reachable at all** (new domain, DNS change, server down). In that case, `get_cert_expiry` returns non-zero and the script goes straight to `renew_cert`.

## Adapting for Your Environment

### Using with Nginx or Apache

Add a deploy hook to reload your web server after renewal:

```bash
# In the certbot command, add:
--deploy-hook "systemctl reload nginx"
```

Or for Apache:
```bash
--deploy-hook "systemctl reload apache2"
```

### DNS-01 Challenge (Wildcard Certs)

Replace `--preferred-challenges http` with:

```bash
--preferred-challenges dns \
--dns-cloudflare \
--dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini
```

Requires the `certbot-dns-cloudflare` plugin (or equivalent for your DNS provider).

### Adding Alerting

Pipe failures to your monitoring stack:

```bash
# Slack webhook on failure
if ! ./ssl-check-renew.sh example.com 30 admin@example.com; then
  curl -X POST -H 'Content-type: application/json' \
    --data '{"text":"SSL renewal failed for example.com"}' \
    "$SLACK_WEBHOOK_URL"
fi
```

### Multiple Domains in One Run

Wrap in a loop:

```bash
for domain in app.example.com api.example.com docs.example.com; do
  ./ssl-check-renew.sh "$domain" 30 admin@example.com
done
```

### Non-Let's Encrypt Certificates

If you use a paid CA (DigiCert, Sectigo, etc.), the check portion still works — it inspects whatever cert the server presents. Only the renewal portion is Let's Encrypt-specific. You could replace `renew_cert()` with a notification function that alerts your team to manually renew.

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Could not retrieve certificate` | Domain doesn't resolve, port 443 blocked, or no cert installed | Verify DNS and firewall rules; check `openssl s_client` manually |
| `certbot not found` | certbot not installed or not in PATH | Install via `apt install certbot`, `brew install certbot`, or `snap install certbot --classic` |
| Renewal fails with challenge error | Port 80 not reachable for HTTP-01 | Ensure port 80 is open and your web server serves `.well-known/acme-challenge/` |
| Wrong cert returned | Missing SNI on multi-domain server | Verify `-servername` flag is present (it is by default in this script) |
| BSD date parse error | Cert date format doesn't match expected pattern | Check `openssl x509 -enddate` output format; adjust `to_epoch()` format string if needed |

# SSL Certificate Auto-Check & Renew

A cross-platform script that monitors SSL certificate expiry and automatically renews via Let's Encrypt (certbot) when expired or approaching expiration. Designed for cron-based automation on production servers.

From [Bashmatica! #5: Adding LLM-Powered Log Analysis to Your Monitoring Stack](https://bashmatica.beehiiv.com/#).

## The Problem

Expired SSL certificates cause browser trust warnings, failed API calls, and customer-facing outages — often discovered at the worst possible time:

```
curl: (60) SSL certificate problem: certificate has expired
```

Let's Encrypt certs expire every 90 days. Even with `certbot renew` available, teams forget to schedule it, misconfigure the timer, or only discover the failure after the cert has already lapsed. This script adds a check-first-then-renew layer with configurable lead time.

## Usage

```bash
# Basic — check cert, renew if expired
./ssl-check-renew.sh example.com

# Custom threshold — renew if expiring within 14 days
./ssl-check-renew.sh example.com 14

# With email for Let's Encrypt registration
./ssl-check-renew.sh example.com 30 admin@example.com
```

## Configuration

All configuration is via CLI arguments:

| Argument | Position | Default | Description |
|----------|----------|---------|-------------|
| `DOMAIN` | 1 (required) | — | Domain to check (e.g., `example.com`) |
| `THRESHOLD_DAYS` | 2 | `30` | Renew if cert expires within this many days |
| `EMAIL` | 3 | (none) | Email for Let's Encrypt account registration |

Script-level defaults (edit in script):

| Variable | Default | Description |
|----------|---------|-------------|
| `LOG_FILE` | `/var/log/ssl-check-renew.log` | Path for log output |
| `CERTBOT_BIN` | auto-detected | Path to certbot binary |

## Requirements

- Bash 4.0+
- openssl (for certificate inspection)
- certbot (for renewal; script will error gracefully if missing)
- sed, date (GNU or BSD)

Works on both Linux and macOS — the script auto-detects GNU vs. BSD `date` for epoch conversion.

## Cron Integration

Add as a daily check:

```bash
sudo crontab -e
# Run daily at 3 AM
0 3 * * * /path/to/ssl-check-renew.sh example.com 30 admin@example.com
```

**Multiple domains:**

```bash
0 3 * * * /path/to/ssl-check-renew.sh app.example.com 30 admin@example.com
5 3 * * * /path/to/ssl-check-renew.sh api.example.com 30 admin@example.com
```

## How It Works

1. Connects to the domain on port 443 via `openssl s_client`
2. Extracts the `notAfter` date from the certificate's x509 data
3. Converts the expiry date to epoch seconds (cross-platform)
4. Compares against current time to compute days remaining
5. If expired or within threshold → runs `certbot certonly` to renew
6. If no cert is reachable at all → attempts to obtain a new one
7. Logs all actions to `/var/log/ssl-check-renew.log`

## Limitations

- Renewal uses `--preferred-challenges http` (HTTP-01 challenge); port 80 must be reachable
- Does not automatically reload web server config after renewal (add a `--deploy-hook` for that)
- No Slack/email alerting on failure (pipe cron output to your alerting tool)
- Single-domain only per invocation (no wildcard/SAN support)

For production hardening, consider adding `--deploy-hook "systemctl reload nginx"` to the certbot command and piping failures to your alerting stack.

## License

MIT License. See [LICENSE](../LICENSE) for details.

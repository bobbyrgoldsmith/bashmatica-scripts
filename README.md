# Bashmatica! Scripts

Demo scripts and code samples from the [Bashmatica! newsletter](https://bashmatica.beehiiv.com), covering AI and automation in DevOps and QA.

## Contents

| Directory | Description | Issue |
|-----------|-------------|-------|
| [webdriver-updater](./webdriver-updater/) | Browser-agnostic Selenium WebDriver auto-updater | [#1: The Hidden Maintenance Tax of Test Automation](https://bashmatica.beehiiv.com/p/bashmatica-1-a-new-shift-on-an-old-problem) |
| [llm-sanitizer](./llm-sanitizer/) | Strip secrets from logs before sending to LLMs | [#2: The Good, The Bad, & The Ugly of LLMs in the Pipeline](https://bashmatica.beehiiv.com/#) |
| [model-compare](./model-compare/) | Compare Claude model tier responses for log analysis | [#3: Not All LLMs Are Equal for DevOps Tasks](https://bashmatica.beehiiv.com/#) |
| [jq-log-parser](./jq-log-parser/) | Structured JSON log parsing utilities with jq | [#4: When "AI-Native" Means "40% Fewer of You"](https://bashmatica.beehiiv.com/#) |
| [ssl-check-renew](./ssl-check-renew/) | Auto-check SSL cert expiry & renew via certbot | [#5: LLMs Never Say "I Don't Know" (and That's the Problem)](https://bashmatica.beehiiv.com/#) |
| [blast-radius-guard](./blast-radius-guard/) | Pre-commit hook to catch destructive patterns in diffs | [#6: 6.3 Million Lost Orders and a 90-Day Reset](https://bashmatica.beehiiv.com/#) |
| [test-integrity-lint](./test-integrity-lint/) | Scan test files for state injection and low assertion density | [#7: The Trust Decay Problem](https://bashmatica.beehiiv.com/#) |
| [assertion-density-check](./assertion-density-check/) | Flag test files that inflate coverage without meaningful assertions | [#8: When the Dashboard Says 94%](https://bashmatica.beehiiv.com/#) |
| [stale-test-finder](./stale-test-finder/) | Find test files that haven't kept pace with their source code | [#9: Q1's 52,000 Cuts Didn't Remove Headcount. They Removed the Feedback Loop.](https://bashmatica.beehiiv.com/#) |
| [weekday-audit](./weekday-audit/) | Scan text files for day-of-week / date mismatches in LLM output | [#10](https://bashmatica.beehiiv.com/#) |

## About Bashmatica!

Bashmatica! is a weekly newsletter for DevOps, QA, and Site Reliability engineers covering:

- **Integration Strategies** - How to add AI and automation to pipelines without breaking production
- **Honest Tool Assessments** - What works, what doesn't, and when to avoid entirely
- **Case Studies** - What's hype vs. what's actually working

Subscribe at [bashmatica.beehiiv.com](https://bashmatica.beehiiv.com).

## Usage

Each directory contains its own README with specific usage instructions. Scripts are designed for Linux CI environments unless otherwise noted.

## Requirements

Most scripts assume:

- Bash 4.0+
- GNU coreutils (grep, awk, etc.)
- curl

Additional requirements are listed in each script's README.

## License

MIT License. See [LICENSE](./LICENSE) for details.

## Author

Bobby R. Goldsmith
[NodeBridge Automation Solutions](https://nodebridge.dev)

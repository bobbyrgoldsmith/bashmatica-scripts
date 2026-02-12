# Bashmatica! Scripts

Demo scripts and code samples from the [Bashmatica! newsletter](https://bashmatica.beehiiv.com), covering AI and automation in DevOps and QA.

## Contents

| Directory | Description | Issue |
|-----------|-------------|-------|
| [webdriver-updater](./webdriver-updater/) | Browser-agnostic Selenium WebDriver auto-updater | [#1: The Hidden Maintenance Tax of Test Automation](https://bashmatica.beehiiv.com/p/bashmatica-1-a-new-shift-on-an-old-problem) |
| [llm-sanitizer](./llm-sanitizer/) | Strip secrets from logs before sending to LLMs | [#2: The Good, The Bad, & The Ugly of LLMs in the Pipeline](https://bashmatica.beehiiv.com/#) |

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

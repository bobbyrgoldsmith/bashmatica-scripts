# Bashmatica! Scripts

Demo scripts and code samples from the [Bashmatica! newsletter](https://bashmatica.beehiiv.com), covering AI and automation in DevOps and QA.

## Contents

| Directory | Description | Issue |
|-----------|-------------|-------|
| [webdriver-updater](./webdriver-updater/) | Browser-agnostic Selenium WebDriver auto-updater | [#1: The Hidden Maintenance Tax of Test Automation](https://www.bashmatica.com/archive/001-a-new-shift-on-an-old-problem/) |
| [llm-sanitizer](./llm-sanitizer/) | Strip secrets from logs before sending to LLMs | [#2: The Good, The Bad, & The Ugly of LLMs in the Pipeline](https://www.bashmatica.com/archive/002-the-good-the-bad-the-ugly-of-llms-in-the-pipeline/) |
| [model-compare](./model-compare/) | Compare Claude model tier responses for log analysis | [#3: Not All LLMs Are Equal for DevOps Tasks](https://www.bashmatica.com/archive/003-the-mid-tier-llm-was-right-the-premium-one-was-wro/) |
| [jq-log-parser](./jq-log-parser/) | Structured JSON log parsing utilities with jq | [#4: When "AI-Native" Means "40% Fewer of You"](https://www.bashmatica.com/archive/004-the-ai-layoff-playbook-just-got-its-first-real-cas/) |
| [ssl-check-renew](./ssl-check-renew/) | Auto-check SSL cert expiry & renew via certbot | [#5: LLMs Never Say "I Don't Know" (and That's the Problem)](https://www.bashmatica.com/archive/005-claude-told-him-to-run-terraform-destroy/) |
| [blast-radius-guard](./blast-radius-guard/) | Pre-commit hook to catch destructive patterns in diffs | [#6: 6.3 Million Lost Orders and a 90-Day Reset](https://www.bashmatica.com/archive/006-amazon-lost-6-3m-orders-ai-was-the-catalyst-not-th/) |
| [test-integrity-lint](./test-integrity-lint/) | Scan test files for state injection and low assertion density | [#7: The Trust Decay Problem](https://www.bashmatica.com/archive/007-the-trust-decay-of-the-green-checkmark/) |
| [assertion-density-check](./assertion-density-check/) | Flag test files that inflate coverage without meaningful assertions | [#8: When the Dashboard Says 94%](https://www.bashmatica.com/archive/008-when-the-dashboard-says-94/) |
| [stale-test-finder](./stale-test-finder/) | Find test files that haven't kept pace with their source code | [#9: Q1's 52,000 Cuts Didn't Remove Headcount. They Removed the Feedback Loop.](https://www.bashmatica.com/archive/009-q1-52k-cut-shift-left-gone/) |
| [mutant-check](./mutant-check/) | Lightweight mutation testing demo for any language and test runner | [#10: 15,000 Artificial Bugs. Facebook's Tests Caught Less Than Half.](https://www.bashmatica.com/archive/010-meta-tests-missed-7-500-bugs/) |
| [weekday-audit](./weekday-audit/) | Scan text files for day-of-week / date mismatches in LLM output | [#11](https://www.bashmatica.com/archive/011-your-agent-says-it-s-monday-your-calendar-knows-it/) |
| [unit-check](./unit-check/) | Validate LLM-emitted unit conversions against deterministic constants; flag inaccuracies and threshold-crossing errors | [#12](https://www.bashmatica.com/archive/012-off-by-exactly-100/) |
| [schema-shadow](./schema-shadow/) | Audit LLM-emitted JSON payloads for failure modes JSON Schema can't catch: dropped fields, type coercion, array drift, field-order drift | [#13](https://www.bashmatica.com/archive/013-the-schema-passed-the-values-lied/) |
| [behavior-canary](./behavior-canary/) | Run a Claude-powered agent against a fixed red-team prompt set before every deploy; diff responses against a baseline for class, length, tone, and refusal-language drift | [#14](https://www.bashmatica.com/archive/014-claude-chose-blackmail-96-of-the-time/) |
| [agent-net](./agent-net/) | Classify an agent's tool manifest by reversibility tier (read-only / reversible-write / irreversible-action / privileged-blast-radius) before deploy | [#15](https://www.bashmatica.com/archive/015-ai-without-a-safety-net/) |
| [receipt-check](./receipt-check/) | Tier the supporting evidence for an AI procurement claim (vendor demo → our pilot) and gate irreversible decisions against the evidence quality | [#16](https://www.bashmatica.com/archive/016-what-pizza-hut-knew-that-meta-didn-t/) |
| [env-drift](./env-drift/) | Compare an expected-key manifest against the actual environment and flag MISSING / EMPTY / EXTRA keys before an app boots into a silent failure | [#17](https://www.bashmatica.com/archive/017-ai-ceos-jeered-off-the-stages/) |
| [gate-keeper](./gate-keeper/) | Refuse to ratify an agent-generated test as a passing gate until it clears an assertion-density floor, a state-manipulation scan, and an independent double-replay | [#18](https://www.bashmatica.com/archive/018-stand-up-agentic-tests-on-your-lunch-break/) |
| [failover-check](./failover-check/) | Refuse a single-homed LLM provider config: flag a missing primary, a fallback that shares the primary's vendor (no real failover), routed providers with no credentials path, unset api_key_env vars, and unrouted provider blocks | [#19](https://www.bashmatica.com/archive/019-feds-pull-fable-5-and-reveal-fragility-of-ai-depen/) |
| [intent-lint](./intent-lint/) | Refuse an incomplete or out-of-sync test-intent manifest before a maintenance agent reads it: flag tests missing intent or criticality, tests with no reachable fallback selectors, and orphaned config/disk references | [#20](https://www.bashmatica.com/archive/020-the-tests-rot-the-manifest-doesn-t/) |
| [samehand](./samehand/) | Flag any pipeline step where the same hand both proposes a change and ratifies it, so a separate ratifier can be put between proposal and merge | [#21: The Agent That Approves Itself](https://www.bashmatica.com/archive/021-the-agent-that-approves-itself/) |
| [judgment-ratio](./judgment-ratio/) | Audit what your automation actually hands off versus what still needs a human standing over it; the honest number behind "the last 20%" | [#22: The Easy 80% Fell Fast. The Last 20% Is Eating Them](https://www.bashmatica.com/archive/022-the-easy-80-fell-fast-the-last-20-is-eating-them/) |
| [ctx-frisk](./ctx-frisk/) | Refuse to let secret-shaped strings into an agent's context window or agent-visible logs; a pre-flight scanner that runs as a blocking gate | [#23: The Agents Know Your Secrets Now](https://www.bashmatica.com/archive/023-the-agents-know-your-secrets-now/) |
| [log-triage](./log-triage/) | Read-only CI-log triage: summarize a failed run and classify it (flaky, infra, or real regression) without letting the agent fix anything or assert a root cause as fact | [#24: Your CI Logs Are a Crime Scene. Let an Agent Read Them](https://www.bashmatica.com/archive/024-your-ci-logs-are-a-crime-scene-let-an-agent-read-t/) |
| [amicus](./amicus/) | Confirm a PR was approved by a human who is not the author; never count a `[bot]` identity as the ratifier | [#25: Let Your AI Reviewer File a Brief, Not a Verdict](https://www.bashmatica.com/archive/025-let-your-ai-reviewer-file-a-brief-not-a-verdict/) |
| [holdstill](./holdstill/) | Run one prompt N times through a model CLI; count distinct outputs, report the first divergent line, and tally the one value that matters | [#26: Temperature Zero Is Not a Lock](https://www.bashmatica.com/archive/026-temperature-zero-is-not-a-lock/) |
| [goldset](./goldset/) | Run a TSV golden set (equals / contains / regex graders) through a model and exit 1 on the first regression | [#27: Evals Are Regression Tests for a Model That Moves](https://www.bashmatica.com/archive/027-evals-are-regression-tests-for-a-model-that-moves/) |
| [fusebox](./fusebox/) | Wrap an agent run in wall-clock, token and dollar ceilings; kill the process group and exit 1 when any fuse trips | [#28: Every Autonomous Run Needs a Fuse](https://www.bashmatica.com/archive/028-every-autonomous-run-needs-a-fuse/) |
| [interlock](./interlock/) | Refuse a bot-authored PR unless the named checks passed and the diff removes no sanitizer and adds no raw `github.event` expansion inside a `run` block | [#29: Uncle Bob Stopped Reading the Code](https://www.bashmatica.com/archive/029-uncle-bob-stopped-reading-the-code/) |
| [ci-clock](./ci-clock/) | Measure how late a scheduled GitHub Actions run fired; export the lag and slot epoch, or fail as LATE CRON, so scheduler lag is never reported as your outage. Ships as a composite action | [#30](https://bashmatica.beehiiv.com/p/030-my-dead-man-switch-ran-on-githubs-clock) |

## About Bashmatica!

Bashmatica! is a weekly newsletter for DevOps, QA, and Site Reliability engineers covering:

- **Integration Strategies** - How to add AI and automation to pipelines without breaking production
- **Honest Tool Assessments** - What works, what doesn't, and when to avoid entirely
- **Case Studies** - What's hype vs. what's actually working

Subscribe at [bashmatica.com](https://www.bashmatica.com/).

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

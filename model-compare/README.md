# model-compare

Compare Claude model tier responses for the same log analysis prompt.

From [Bashmatica! #3: Not All LLMs Are Equal for DevOps Tasks](https://bashmatica.beehiiv.com).

## The Problem

Engineers default to the most expensive model assuming it's the best. For most DevOps log analysis tasks, mid-tier models (Sonnet) match premium tier (Opus) quality at a fraction of the cost and latency. This script lets you verify that claim against your own logs.

## Quick Start

```bash
chmod +x compare_llm_models.sh

# From a file
./compare_llm_models.sh "Identify the root cause" /var/log/app/error.log

# From stdin
kubectl logs deployment/api | tail -100 | ./compare_llm_models.sh "Diagnose these failures"

# With the sanitizer from Issue #2
cat error.log | ../llm-sanitizer/sanitize.sh | ./compare_llm_models.sh "Root cause analysis"
```

## What It Does

1. Sends the same prompt and log data to Claude Sonnet and Claude Haiku
2. Displays both responses with wall-clock timing
3. You compare quality and latency for your specific log patterns

The point isn't that one model is universally better. It's that for your workload, you can make an informed decision about which tier to use.

## Requirements

- Bash 4.0+
- curl
- jq
- `ANTHROPIC_API_KEY` environment variable

## Customization

To compare different models, edit the two `query_model` calls at the bottom of the script. Swap in any model ID:

| Tier | Model ID |
|------|----------|
| Premium | `claude-opus-4-6` |
| Mid-tier | `claude-sonnet-4-6` |
| Budget | `claude-haiku-4-5-20251001` |

## Shell Function Version

If you prefer sourcing a function rather than running a standalone script, add this to `~/.bashrc` or `~/.zshrc`:

```bash
compare_llm_models() {
    local prompt="$1"
    local log_snippet="$2"

    echo "=== Claude Sonnet ==="
    time curl -s https://api.anthropic.com/v1/messages \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "content-type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d "$(jq -n --arg p "$prompt" --arg l "$log_snippet" '{
            model: "claude-sonnet-4-6",
            max_tokens: 1000,
            messages: [{role: "user", content: "\($p)\n\n\($l)"}]
        }')" | jq -r '.content[0].text'

    echo -e "\n=== Claude Haiku ==="
    time curl -s https://api.anthropic.com/v1/messages \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "content-type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d "$(jq -n --arg p "$prompt" --arg l "$log_snippet" '{
            model: "claude-haiku-4-5-20251001",
            max_tokens: 1000,
            messages: [{role: "user", content: "\($p)\n\n\($l)"}]
        }')" | jq -r '.content[0].text'
}

# Usage
compare_llm_models "Identify the root cause of failures in these logs:" "$(tail -100 /var/log/app/error.log)"
```

## Limitations

- Compares two models only (edit script to add more)
- No output formatting beyond raw model responses
- API rate limits apply; space requests if running in a loop
- Does not sanitize input; pair with [llm-sanitizer](../llm-sanitizer/) for sensitive logs

## License

MIT License. See [LICENSE](../LICENSE).

---

Part of the [Bashmatica!](https://bashmatica.beehiiv.com) newsletter by Bobby R. Goldsmith.

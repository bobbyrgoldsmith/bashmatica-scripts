# agent-net

Classify an agent's tool manifest by **reversibility tier** before deploy.

Companion script for [Bashmatica! #15: Claude Will Now Pay Your Bills And Sign Your Contracts. Nobody Built The Net.](https://www.bashmatica.com/archive/015-nobody-built-the-net/).

## The problem

Modern agentic AI products surface a single consent gate ("Approve before anything sends, posts, or pays") that asks a human to authorize an action without telling them what kind of action it is. A query against the database, a draft email, an Instagram post, and a wire transfer all reach the operator as the same blue button. The blast radius is wildly different in each.

`agent-net` reads your agent's tool manifest and classifies each tool into one of four reversibility tiers:

- **read-only** — no external write. Worst case is exposed data.
- **reversible-write** — internal write with a clear undo path (draft, save, update internal state).
- **irreversible-action** — outbound communication or external state change without easy undo (send email, post publicly, schedule meeting).
- **privileged-blast-radius** — touches money, contracts, identity, or counterparty notification (wire payment, send DocuSign, refund, cancel subscription).

The output is a per-tool scorecard you commit alongside the agent's deploy config so the audit trail lives in the same repo as the agent.

## Install

```bash
git clone https://github.com/bobbyrgoldsmith/bashmatica-scripts.git
cd bashmatica-scripts/agent-net
chmod +x agent-net.sh
```

Hard dependency: `jq` (`brew install jq`).

Targets bash 3.2+ — macOS-compatible out of the box.

## Usage

### Run against an MCP `tools/list` response

```bash
./agent-net.sh --manifest path/to/manifest.json
```

The manifest must have shape `{ "tools": [ { "name": ..., "description": ..., "inputSchema": {...}, "requires_confirmation"?: bool } ] }`.

### Run against a flat JSON array

```bash
./agent-net.sh --list path/to/tools.json
```

Where `tools.json` is `[ { "name": ..., ... }, ... ]` directly.

### Run against the bundled example

```bash
./agent-net.sh --example
```

### Output formats

```bash
./agent-net.sh --manifest m.json --format markdown   # default
./agent-net.sh --manifest m.json --format json
./agent-net.sh --manifest m.json --format csv
```

### Deploy gating

```bash
./agent-net.sh --manifest m.json --strict
```

Exits non-zero if any tool above `reversible-write` lacks an explicit `"requires_confirmation": true` field in its definition. Wire this into a CI step to refuse deploys that haven't acknowledged every irreversible action with a confirmation gate.

`--ci` is an alias for `--strict --format markdown`.

## Classification approach

Patterns are matched against the tool **name only**, not the description or schema. Two reasons:

1. **Descriptions reference other tools.** A tool described as "Create a draft. Send is performed by `send_invoice`" contains the word "send" but does not itself send. Schema enum values (`"status": "draft"`) similarly trigger false positives on object names.
2. **Tools should be named for what they do.** If `do_thing(x)` is your tool name, the classifier has nothing to work with — and that's the operator's signal to fix the name, not the classifier.

Tiers are evaluated highest-risk first. Anything that matches a higher tier is assigned that tier; nothing matched falls through to `read-only`. This is conservative-by-default: the cost of over-classifying is a few extra confirmation clicks, and the cost of under-classifying is an unrecoverable action.

### Current patterns

- `privileged-blast-radius`: `wire`, `ach`, `docusign`, `charge`, `refund`, `terminate`, `delete_account`, `revoke_access`, `grant_access`, `provision`, `send_invoice`, `sign_contract`, `cancel_subscription`
- `irreversible-action`: `send`, `post`, `publish`, `notify`, `deploy`, `broadcast`, `email`, `sms`, `webhook`, `schedule_meeting`, `create_user`/`customer`/`order`/`account`, `delete`
- `reversible-write`: `draft`, `save`, `update`, `write`, `store`, `cache`, `set`, `patch`, `upsert`, `tag`, `label`, `annotate`
- `read-only`: default

Patterns are conservative starting points; extend them for your domain. The script is intentionally short (~200 lines) so you can read and modify it in a single sitting.

## Suggested workflow

The Bashmatica #15 "Quick Wins" path:

1. **(15 min)** Write down every tool wired into your highest-stakes agent and assign each one to a reversibility tier by hand.
2. **(1 hour)** Run `agent-net` against the same agent's manifest. Diff against your hand classification. Reconcile differences — the script is conservative, so it will surface counterparty-notification side effects you forgot about.
3. **(half day)** Wire the classification into runtime as a hard refusal gate. Anything `irreversible-action` or `privileged-blast-radius` requires a second human confirmation captured outside the agent's UI (Slack approval, email reply, PIN on a separate channel) before the action fires. Log every fired action with its reversibility tag, the confirming human's identity, and the timestamp.

## Related scripts in this repo

- [`blast-radius-guard`](../blast-radius-guard/) — git-diff scanner that catches destructive shell patterns at commit time (counterpart of `agent-net` at the source-control layer).
- [`behavior-canary`](../behavior-canary/) — pre-deploy red-team prompt runner that diffs agent responses against a known-good baseline (Bashmatica #14).

Together, the three form a small coherent toolkit: `blast-radius-guard` watches what humans+AI write into source, `behavior-canary` watches how the agent responds, and `agent-net` watches what the agent's tools are allowed to do.

## License

MIT. See repo root.

## Hand-raiser

Reply to the Bashmatica #15 thread with `AGENTNET` to receive the script + an example MCP manifest + the 4-tier rule set in a single DM.

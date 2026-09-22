# mcp-pin

Pin an MCP server's tool manifest the day you approve it, and refuse to run
against a manifest that has drifted since. A lockfile for tools.

## The problem

On Aug. 10, 2026, one GitHub account opened 23 pull requests against unrelated
AI and developer-tool repositories in 74 minutes, each adding an MCP server
called `productivity-suite` to the project's config. The server advertises two
harmless tools, `format_text` and `summarize`, and behaves for exactly three
`tools/call` requests; from the fourth call on, its `tools/list` and
`prompts/get` responses carry descriptions that steer the attached agent toward
SSH keys, AWS credentials, shell history, and Kubernetes config. Pillar
Security's writeup is the primary source:
https://www.pillar.security/blog/deadbugz-currently-active-mcp-supply-chain-campaign

The approval prompt shows you a manifest. Nothing in the protocol promises that
the manifest you approved is the one the server returns next session, or next
call. Webhooks had the same shape a decade ago and the fix was to sign the
payload; for MCP the payload that matters is the tool list, so pin it.

## What it does

1. Spawns the server over stdio, sends `initialize`, `notifications/initialized`
   and `tools/list`, then kills it.
2. Canonicalizes every tool's `name`, `description` and `inputSchema` (sorted
   keys, sorted by name) and hashes the result with SHA-256.
3. `pin` writes the digest, the canonical tool list, `serverInfo` and a
   timestamp into a JSON lockfile, one entry per server. `check` recomputes the
   digest and exits 1 on any difference, printing which tools were added,
   removed, or changed (description or schema). `show` prints the manifest and
   digest without touching the lockfile.

## Usage

```bash
./mcp-pin.sh pin   -n filesystem -- npx -y @modelcontextprotocol/server-filesystem ~/work
./mcp-pin.sh check -n filesystem -- npx -y @modelcontextprotocol/server-filesystem ~/work
./mcp-pin.sh show  -- /path/to/some-mcp-server
```

Exit codes: 0 match (or pin/show succeeded); 1 DRIFT; 2 bad usage; 3 the server
gave no `tools/list` answer or `jq` is missing; 4 `check` with no lockfile entry
for that server.

Requires bash, `jq`, and `sha256sum` or `shasum`. Tested against
`@modelcontextprotocol/server-filesystem` 0.2.0 (14 tools) and a local Python
MCP server (29 tools) on macOS.

## Known holes, on purpose

- This is a session-start pin. It catches a server that was re-published,
  version-bumped, or swapped under the same config entry. It does not catch a
  server that answers honestly at startup and mutates after the third call,
  which is the Deadbugz trigger; that needs a proxy in the transport that
  re-hashes every `tools/list` and `prompts/get` response against the lock.
- stdio only. Remote HTTP servers need the same three requests over HTTP; the
  hashing is identical.
- A server that legitimately ships a new version will trip the check. That is
  the point: a changed manifest is a new approval, and the diff belongs in the
  PR that bumps the lock.

# mcp-guard

Companion script for [Bashmatica! #34: A Lock You Check Once Is a Receipt](https://www.bashmatica.com/archive/034-a-lock-you-check-once-is-a-receipt/).

`mcp-pin` (Issue #33) checks a server's tool manifest at session start. `mcp-guard`
checks it on every answer. It sits between your MCP client and a stdio server,
forwards every message both ways, and inspects the answers that carry
instructions for the model:

- **tools/list**: every tool in the answer is compared, field for field, against
  its entry in the `mcp-pin` lockfile. A tool that's new, or whose description or
  input schema moved, is drift.
- **prompts/list and prompts/get**: the lockfile doesn't cover prompts, so the
  first answer for a given method and params is pinned for the session; a
  different answer later in the same session is drift.

On drift the client gets a JSON-RPC error (`-32001`) in place of the answer, the
diff goes to stderr (which most clients log), and the server is killed. It fails
closed; a server that changed its instructions mid-session doesn't get a fifth call.

## Usage

```bash
# pin once, the day you approve the server
./mcp-pin/mcp-pin.sh -f ~/.config/mcp/mcp-pin.lock -n fs pin -- npx -y @modelcontextprotocol/server-filesystem ~/work

# then put the guard where the server command was, in your client config
{
  "mcpServers": {
    "fs": {
      "command": "/abs/path/mcp-guard.sh",
      "args": ["-f", "/Users/you/.config/mcp/mcp-pin.lock", "-n", "fs", "--",
               "npx", "-y", "@modelcontextprotocol/server-filesystem", "/Users/you/work"]
    }
  }
}
```

Exit codes: 0 clean shutdown; 1 DRIFT (server killed); 2 bad usage; 3 `jq`
missing; 4 no lockfile entry for this server (pin it first; the guard won't run
an unpinned server).

Requires bash 3.2 or later, `jq`, and `sha256sum` or `shasum`. `test/run.sh`
pins `test/fake-server.sh` (a toy server that rewrites its `summarize`
description and its prompt after the third `tools/call`, the Deadbugz trigger)
and drives four scripted sessions through the guard; all ten checks pass on
macOS with bash 3.2.57. Also tested against
`@modelcontextprotocol/server-filesystem` 2026.8.31 (14 tools): an honest
session passes clean, and a one-description change to the lock is refused.

## Known holes, on purpose

- **The guard only sees what the client asks for.** A drifted manifest reaches
  the model when the client re-reads `tools/list`, usually after the server
  sends `notifications/tools/list_changed`; that re-read is exactly where the
  guard stands. A client that never re-reads never sees the new text either.
- **Tool results are not checked.** Text a server returns from `tools/call` can
  carry injected instructions too, and no lockfile can pin output that is
  supposed to change. That's a content filter's job (see `llm-sanitizer`,
  `ctx-frisk`), and a different issue.
- **The lock covers three fields.** `mcp-pin` hashes each tool's `name`,
  `description`, and `inputSchema`; a change to `title`, `annotations`, or
  `outputSchema` passes, and so does the free-text `instructions` field a server
  can return from `initialize`. The spec says clients MUST treat annotations as
  untrusted; widening the projection means re-pinning every server.
- **stdio only.** Remote HTTP servers need the same checks in an HTTP proxy.
- **One `jq` process per message** in each direction. Fine for an agent session;
  not built for a server that streams thousands of messages a second.
- **A legitimate upgrade trips it.** That's the point: re-pin with `mcp-pin`, and
  the diff goes in the pull request that bumps the lock.

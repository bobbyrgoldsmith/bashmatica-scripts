# egress-fence

Run a command as an unprivileged user whose outbound traffic is limited, in the
kernel, to the hosts you name. Everything else is logged, counted, and refused.

## The problem

In July 2026 roughly 1,200 OpenAI eval agents, each in its own sandbox,
discovered they shared one writable package cache (Artifactory, reachable over
WebDAV) and turned it into a message board; about 700 of them then used leaked
credentials to break into Hugging Face, a company that had nothing to do with
the task. Nothing in the assignment needed any host beyond the package cache.
The sandbox never said so. METR's investigation is the primary source:
https://metr.org/blog/2026-08-26-openai-hugging-face-incident-investigation/

That is a CONTAINMENT failure: the sandbox has to be designed on the assumption
that whatever runs inside it will try to leave. `egress-fence` is the network
half of that design.

## What it does

1. Resolves the allowlist once, before the fence goes up. A name that fails to
   resolve fails the run (exit 4).
2. Creates an iptables chain keyed on the `owner` match for a dedicated
   unprivileged user (`fenced` by default, created if absent). Loopback, the
   resolvers in `/etc/resolv.conf` on port 53, and the resolved addresses are
   accepted; everything else is logged with an `EGRESS_FENCE REFUSED` prefix,
   counted, and rejected with `icmp-admin-prohibited`. IPv6 from that user is
   refused outright rather than left as a second door.
3. Runs your command as that user via `setpriv`, so it never held the
   privilege to touch the rules.
4. Tears the chain down on exit, prints the refused-packet count, and passes
   the command's exit code through. With `--strict`, any refusal exits 5.

## Usage

```bash
sudo ./egress-fence.sh -a api.anthropic.com,pypi.org,files.pythonhosted.org -- python3 agent.py
sudo ./egress-fence.sh -a 10.0.0.0/8 --strict -- ./run-eval.sh
```

Exit codes: the command's own; 2 bad usage; 3 not root or `iptables`/`setpriv`/
`getent` missing; 4 an allowlist entry did not resolve; 5 refusals under
`--strict`.

## Known holes, on purpose

- DNS to your own resolver is allowed, because a fence that breaks name
  resolution gets deleted by Friday. If DNS tunneling is in your threat model,
  point `/etc/resolv.conf` at a resolver that logs.
- The allowlist resolves once at startup. A host that round-robins across a
  CDN wants a CIDR.
- IPv4 only. IPv6 is refused for the fenced user, not allowlisted.
- Linux only (`iptables`, `setpriv`). On a GitHub-hosted Ubuntu runner all
  three tools are present and the workflow user has passwordless sudo.

## Companion issue

Bashmatica! #32, "The Grader Didn't Exist" (Sept. 15, 2026):
https://www.bashmatica.com/archive/032-the-grader-didnt-exist/

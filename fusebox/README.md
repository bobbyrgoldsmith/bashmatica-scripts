# fusebox

Wrap an agent run in three hard ceilings, wall-clock, tokens and dollars, and kill
the whole process group the instant any one of them trips.

## The problem

In May 2026 an unsupervised agent told to scan the DN42 hobbyist network decided it
needed infrastructure, provisioned five of the largest EC2 instances it could
reach plus load balancers and Lambda functions, and ran up $6,531.30 in under 24
hours, for a job a $5 VPS would have handled. Nothing in the model malfunctioned.
It reasoned its way, step by confident step, into the bill, because nothing in
its environment was built to tell it when to stop.

An agent is not a function call. It is a loop that feeds its own output back in,
and the context grows with every turn: Anthropic's own numbers put a single agent
at about four times the tokens of a chat interaction and a multi-agent system at
about 15 times. A stuck step retried 40 times looks like progress from the
inside. The cost of a run is not a function of how hard the work is; it is a
function of how long the thing runs before something makes it stop, and in most
pipelines nothing does. The invoice becomes the circuit breaker, which is the most
expensive place to discover you needed one.

The fix is the oldest idea in electrical safety: a cheap component whose whole
job is to fail first. `fusebox` is that component. Size each ceiling at two to
three times the worst normal run you measured, and when it blows, stop, page and
wait; a fuse that lets a scheduler restart the loop from the top is a slower,
more expensive loop.

## Usage

The wrapped command appends one integer per model call (tokens used) to the file
named in `$FUSE_USAGE`, which `fusebox` exports before starting it.

```bash
./fusebox.sh ./run-agent.sh                                   # defaults: 900s, 500k tokens, $20
MAX_SECONDS=3600 MAX_USD=50 ./fusebox.sh ./run-agent.sh        # a longer, dearer job
MAX_TOKENS=50000 MAX_USD=1 USD_PER_MTOK=15 ./fusebox.sh examples/runaway-agent.sh
./examples/demo.sh                                            # the runaway loop from Issue #28
```

Sample run against `examples/runaway-agent.sh`, which logs 8,000 tokens a second
and never exits:

```
FUSEBOX: BLOWN - tokens 56000 >= 50000
$ echo $?
1
```

## Fuses and exit codes

| Variable | Default | Trips when |
|----------|---------|------------|
| `MAX_SECONDS` | 900 | elapsed wall-clock reaches the ceiling |
| `MAX_TOKENS` | 500000 | sum of `$FUSE_USAGE` reaches the ceiling |
| `MAX_USD` | 20 | tokens x `USD_PER_MTOK` / 1,000,000 reaches the ceiling |
| `USD_PER_MTOK` | 15 | blended price used for the dollar fuse |
| `FUSE_USAGE` | temp file | where the wrapped command appends per-call token counts |

| Code | Meaning |
|------|---------|
| 0 | run completed inside every fuse; total tokens printed |
| 1 | `FUSEBOX: BLOWN`: a fuse tripped and the process group was sent SIGTERM |
| 2 | no command given |

The fuses are polled every 2 seconds, so a trip can overshoot the ceiling by one
poll's worth of usage. That is the point of a fuse rated with headroom.

## Requires

- bash 3.2+
- `awk`, `kill`, `mktemp`
- `setsid` where available (util-linux). On macOS, which has no `setsid`, the script
  falls back to bash job control (`set -m`) to give the child its own process group.

## Related scripts in this repo

- [interlock](../interlock/) (#29): the gate that refuses a bot-authored diff on
  review alone. `fusebox` bounds the run; `interlock` bounds what the run may merge.
- [ci-clock](../ci-clock/) (#30): a fuse needs a clock that is not borrowed from
  the platform it guards.
- [agent-net](../agent-net/) (#15): classify the agent's tools by blast radius
  before you decide how big a fuse it earns.

## From the newsletter

Companion script for
[Bashmatica! #28: Every Autonomous Run Needs a Fuse](https://www.bashmatica.com/archive/028-every-autonomous-run-needs-a-fuse/).
Hand-raiser keyword: FUSEBOX.

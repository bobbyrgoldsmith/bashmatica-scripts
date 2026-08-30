# ci-clock

Measure how late GitHub actually ran a scheduled workflow, then hand that number
to the check that runs next, so scheduler lag never gets reported as your outage.

## The problem

A `schedule:` trigger is a request, not an appointment. GitHub's own docs carry
the caveat, and in a normal week the lag is 20 to 30 minutes. In the last week
of August 2026, mid-migration and mid-incident, the same 22:15 UTC slot fired at
03:17, 06:06 and 03:42 the following mornings: five, eight and five and a half
hours late.

Any check that asks "did X happen in the last N hours?" fails by construction
when it runs N+1 hours late. That is a monitor with a BORROWED CLOCK: its sense
of time comes from the platform it is supposed to be watching. The Vigilant's
dead-man switch false-alarmed three nights running for exactly this reason while
the newsletter it guards went out on time every day.

`ci-clock` runs as the first step of the workflow, works out the most recent
occurrence of the cron slot you name, compares it to the wall clock, prints the
lag, and then does one of two things:

- writes `CI_CLOCK_LAG_SEC`, a widened `CI_CLOCK_WINDOW_SEC` and
  `CI_CLOCK_SLOT_EPOCH` to `$GITHUB_ENV` (and the same three as step outputs)
  for the check that follows, or
- if `CI_CLOCK_MAX_LAG` is set and exceeded, fails the run with a message that
  names the platform: `LATE CRON: GitHub ran the 22:15 slot 28301s late`.

The better dead-man does not need the window at all. With the slot epoch in hand
it asserts "a real item published after the send time on the slot's date", which
is true at 22:15 and still true at 06:06.

## Usage

As a composite action (pin to a commit SHA in production):

```yaml
- name: Measure scheduler lag
  id: clock
  uses: bobbyrgoldsmith/bashmatica-scripts/ci-clock@master
  with:
    slot: "22:15"       # the UTC cron slot this workflow is scheduled for
    max-lag: "14400"    # optional: more than 4h late fails as LATE CRON
- run: echo "fired ${{ steps.clock.outputs.lag-sec }}s late; slot epoch ${{ steps.clock.outputs.slot-epoch }}"
```

As a script:

```bash
./ci-clock.sh 22:15                                   # prints lag, widens the window
CI_CLOCK_MAX_LAG=14400 ./ci-clock.sh 22:15            # exit 2 with LATE CRON when over 4h late
CI_CLOCK_NOW=1787897201 ./ci-clock.sh 22:15           # replay a past run offline
./examples/demo.sh                                    # the three late fires behind Issue #30
```

`examples/deadman.yml` is a complete workflow that uses the slot epoch to assert
"published today after the send time" instead of "in the last N hours".

## Inputs and environment

| Script env | Action input | Default | Meaning |
|------------|--------------|---------|---------|
| argument 1 | `slot` | required | UTC cron slot as `HH:MM` |
| `CI_CLOCK_WINDOW_SEC` | `window-sec` | `10800` | base window the downstream check uses; the lag is added to it |
| `CI_CLOCK_MAX_LAG` | `max-lag` | `0` (off) | lag in seconds that fails the run outright |
| `CI_CLOCK_NOW` | `now` | wall clock | epoch override for offline replay |

Outputs: `lag-sec`, `window-sec`, `slot-epoch` (also exported to `$GITHUB_ENV` as
`CI_CLOCK_LAG_SEC`, `CI_CLOCK_WINDOW_SEC`, `CI_CLOCK_SLOT_EPOCH`).

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | lag measured and exported |
| 2 | LATE CRON: lag exceeded `CI_CLOCK_MAX_LAG`, or the slot argument was malformed |

## Requires

- Bash 4+
- GNU `date` (`-d`) or BSD `date` (`-j -f`); both paths are handled, and the
  slot parse includes seconds so BSD `date` cannot borrow them from the wall clock

## Related scripts in this repo

- [`fusebox`](../fusebox/) (Issue #28): the ceiling that trips an autonomous run
- [`interlock`](../interlock/) (Issue #29): the gate that refuses a bot-authored diff on review alone

Both need a clock and a trust root that are not borrowed from the system they guard.

## From the newsletter

Companion script for [Bashmatica! #30](https://bashmatica.beehiiv.com/p/030-my-dead-man-switch-ran-on-githubs-clock).
Hand-raiser keyword: CICLOCK.

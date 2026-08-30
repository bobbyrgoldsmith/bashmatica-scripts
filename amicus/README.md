# amicus

Confirm that a pull request was approved by a human who is not its author, and
never let a bot identity count as the ratifier.

## The problem

AI code review is a default now, not an experiment. A model reads a bounded diff
against a clear question and does it well: it catches the off-by-one a tired
reviewer skims past at 4 p.m., and it does it in 90 seconds. The trouble is not
that these tools review. The trouble is what the review gets to count as.

The moment the bot's "no blocking issues found" becomes the thing a human
rubber-stamps, or the bot's approval satisfies a required check on its own, a tool
that was only ever qualified to offer an opinion has become the hand that ratifies
the merge. That hand can be steered with a sentence: a PR title or a comment in
the diff that tells the reviewer what to write in its summary is one merge key
away from mattering. SLSA's source requirements say it plainly: a protected branch
needs two trusted persons, and a "trusted robot" is not one of them.

The borrowed discipline is amicus curiae, the friend of the court. The agent files
a brief; the verdict stays with someone you can name in the incident review.
`amicus` checks the one thing the branch-protection UI makes easy to get wrong: at
least one APPROVED review came from a human login that is not the author, and no
`[bot]` account is being counted as the second key.

## Usage

Run inside the repository with `gh` authenticated:

```bash
./amicus.sh 128                                   # PR number
./amicus.sh https://github.com/org/repo/pull/128  # or the PR URL
```

Sample output:

```
note: bot approval present (advisory only): coderabbitai[bot]
AMICUS: BLOCKED - no approving review from a human other than the author (bobby).
The only thing between this diff and main is a machine or the author. Get a second key.
```

Wire it as a pull-request check and a change cannot reach `main` on a bot's say-so,
or on the author approving their own work, unless someone decides on purpose to
allow it. The bot's comments still show up and still catch the null check. They no
longer count as the vote.

## Verdicts and exit codes

| Verdict | Meaning | Exit |
|---------|---------|------|
| `AMICUS: OK` | at least one APPROVED review from a human login other than the author | 0 |
| `AMICUS: BLOCKED` | every approval is from the author or from a `[bot]` account, or there are none | 1 |
| usage error | no PR argument given | 1 |

Bot approvals are listed as a note and never counted. GitHub marks automation
accounts with a `[bot]` login suffix, which is what the filter keys on.

## Requires

- bash 3.2+
- `gh` CLI, authenticated against the repository
- `jq`

## Related scripts in this repo

- [gate-keeper](../gate-keeper/) (#18): refuse to ratify an agent-generated test as
  a passing gate until it clears deterministic checks. `gate-keeper` guards
  generated tests; `amicus` guards the approval itself.
- [samehand](../samehand/) (#21): the proposer-never-ratifies principle this issue
  sits on top of.
- [interlock](../interlock/) (#29): for bot-authored diffs, go one step further and
  require passing deterministic checks plus an intact sanitizer before merge.

## From the newsletter

Companion script for
[Bashmatica! #25: Let Your AI Reviewer File a Brief, Not a Verdict](https://www.bashmatica.com/archive/025-let-your-ai-reviewer-file-a-brief-not-a-verdict/).
Hand-raiser keyword: AMICUS.

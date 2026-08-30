# interlock

Refuse a bot-authored or bot-co-authored pull request unless the named
deterministic checks passed and the diff leaves every sanitizer in place.

## The problem

On June 18, 2026, a commit co-authored by GitHub Copilot Autofix landed in
Snowflake's public `snowflake-connector-net` repository. It removed the
sanitized-input pattern a GitHub Actions workflow had been using and replaced it
with a raw `${{ github.event.issue.title }}` expansion inside a `run` block, the
textbook shape of script injection in CI. Five days later Wiz's autonomous
red-team agent found it during a routine sweep, opened an issue with a title
crafted to break out of the echo, and walked off with a Jira token. A human had
reviewed the diff. The label said it was a fix.

The same week Robert C. Martin said he barely looks at the code anymore and
reports a 5x gain. The difference between him and Snowflake is a piece of
industrial-safety vocabulary: an interlock, the mechanism that makes a press
physically unable to run while the guard is open. An interlock is deterministic,
it can fail the run rather than file a comment, and it cannot be argued with by a
prompt, a label or a co-author line. Mutation scores, complexity budgets, lint,
tests and a fuse are interlocks. A bot review, a self-audit and a tired human at
4 p.m. are advisors. Letting go of the wheel is legitimate only inside the
interlocks, and CI configuration is the trust boundary where it never is.

`interlock` is the pre-merge gate for that boundary. Human-only PRs pass straight
through; review remains the control there. For anything with a bot in the author
or co-author list it requires passing checks and an intact guard, and it prints
the exact line that tripped it.

## Usage

Against a live pull request (needs `gh`):

```bash
./interlock.sh org/repo 128
INTERLOCK_CHECKS=test,lint,mutation ./interlock.sh org/repo 128
```

Offline, against a diff file:

```bash
INTERLOCK_DIFF=snowflake-shaped.diff INTERLOCK_CHECKS=test INTERLOCK_PASSED=test ./interlock.sh
./examples/demo.sh      # the Snowflake-shaped diff from Issue #29
```

Sample run:

```
$ INTERLOCK_DIFF=snowflake-shaped.diff INTERLOCK_CHECKS=test INTERLOCK_PASSED=test ./interlock.sh
INTERLOCK: OPEN - sanitizer removed:
-        TITLE=$(sanitize_input "$ISSUE_TITLE")
$ echo $?
1
```

The tests passed, which is the situation that fooled the reviewer, and the
interlock refused anyway on the first guard it found coming off.

| Variable | Default | Meaning |
|----------|---------|---------|
| `INTERLOCK_CHECKS` | `test,lint` | comma-separated check names that must have SUCCESS state |
| `INTERLOCK_BOTS` | `copilot\|autofix\|dependabot\|\[bot\]` | case-insensitive regex of bot identities |
| `INTERLOCK_DIFF` | unset | path to a diff; skips `gh` entirely |
| `INTERLOCK_AUTHORS` | `copilot-autofix[bot]` | author list for offline runs |
| `INTERLOCK_PASSED` | empty | newline-separated check names treated as passed (offline only) |

## Checks and exit codes

| Check | What it catches | Verdict |
|-------|-----------------|---------|
| bot author | no bot in author or co-author list: pass through untouched | CLOSED, exit 0 |
| required checks | a name in `INTERLOCK_CHECKS` that did not complete with SUCCESS | OPEN, exit 1 |
| sanitizer removed | a `-` line mentioning sanitize, escape, quote, shellcheck, allowlist or whitelist | OPEN, exit 1 |
| raw expansion added | a `+` line with `${{ github.event.*.title\|body\|ref\|label\|name\|message\|login }}` | OPEN, exit 1 |

Exit 2 means a usage error (no repo and PR number in online mode).

## Requires

- bash 3.2+
- `grep -E`
- `gh` CLI, authenticated, for online runs (not needed with `INTERLOCK_DIFF`)

## Related scripts in this repo

- [amicus](../amicus/) (#25): the advisor that never ratifies; `interlock` is the
  gate for the diffs where a human nod is not enough.
- [fusebox](../fusebox/) (#28): the ceiling that trips an autonomous run; a fuse
  and an interlock are the two controls that cannot be talked out of their answer.
- [ci-clock](../ci-clock/) (#30): a clock that is not borrowed from the system the
  gate guards.
- [blast-radius-guard](../blast-radius-guard/) (#6): the first pre-commit gate in
  this lineage.

## From the newsletter

Companion script for
[Bashmatica! #29: Uncle Bob Stopped Reading the Code](https://www.bashmatica.com/archive/029-uncle-bob-stopped-reading-the-code/).
Hand-raiser keyword: INTERLOCK.

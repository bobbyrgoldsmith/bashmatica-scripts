# Blast Radius Guard

A pre-commit hook and CI check that scans git diffs for destructive patterns: ORM footguns, infrastructure destroyers, filesystem nukes, and force flags that bypass safety prompts.

From [Bashmatica! #6: 6.3 Million Lost Orders and a 90-Day Reset: What Amazon Learned About AI Guardrails](https://bashmatica.beehiiv.com/#).

## The Problem

AI coding tools and fast-moving teams produce changes faster than review processes can absorb them. The commands that cause the most damage are often a single flag away from safe operation:

```
drizzle-kit push --force     # wiped 60+ tables (Claude Code GitHub #27063)
prisma db push --accept-data-loss  # destroyed production data (#14411)
alembic downgrade base       # dropped 21 tables (#26913)
terraform destroy            # deleted an entire production stack
```

This script catches these patterns in staged changes before they reach your pipeline.

## Usage

### As a pre-commit hook

```bash
cp blast-radius-guard.sh /path/to/your/repo/.git/hooks/pre-commit
chmod +x /path/to/your/repo/.git/hooks/pre-commit
```

Any `git commit` will now scan staged changes for destructive patterns and block the commit if any are found.

### Standalone

```bash
# Check staged changes (same as pre-commit)
./blast-radius-guard.sh

# Check a branch diff against main
./blast-radius-guard.sh --diff "git diff main..feature-branch"

# Check a specific commit
./blast-radius-guard.sh --diff "git show abc123"
```

### CI integration

```yaml
# GitHub Actions example
- name: Blast radius check
  run: |
    git diff ${{ github.event.pull_request.base.sha }}..HEAD > /tmp/pr.diff
    ./blast-radius-guard.sh --diff "cat /tmp/pr.diff"
```

## Built-in Patterns

The script detects destructive patterns across several categories:

| Category | Patterns |
|----------|----------|
| Infrastructure | `terraform destroy`, `pulumi destroy`, `cdk destroy`, `aws * delete-*`, `gcloud * delete`, `az * delete` |
| Database / ORM | `DROP TABLE`, `TRUNCATE TABLE`, `DELETE FROM`, `downgrade base`, `--accept-data-loss`, `--force` (ORM context), `prisma migrate reset` |
| Git | `git push --force`, `git reset --hard`, `git clean -f` |
| Filesystem | `rm -rf`, `rm -fr` |
| Containers | `docker system prune -a`, `kubectl delete namespace` |

## Custom Patterns

Add project-specific patterns via a file (one regex per line):

```bash
# my-patterns.txt
flyway\s+clean
rake\s+db:drop
mongosh.*dropDatabase
```

```bash
# Use with --patterns flag
./blast-radius-guard.sh --patterns my-patterns.txt

# Or set via environment variable
export BLAST_RADIUS_PATTERNS=my-patterns.txt
./blast-radius-guard.sh
```

## Overriding

When a destructive operation is intentional (you've reviewed it, you mean it):

```bash
BLAST_RADIUS_ALLOW=1 git commit -m "intentional: reset staging migration history"
```

The override is per-invocation and logged. It requires explicit action, which is the point: the default is safe, and opting in to danger is a conscious decision.

## Options

| Flag | Description |
|------|-------------|
| `--diff CMD` | Custom diff command (default: `git diff --cached --unified=0`) |
| `--patterns FILE` | Load additional patterns from file |
| `--list` | Print all active patterns and exit |
| `--quiet` | Suppress explanations, print only matched lines |
| `-h, --help` | Show help |

## Requirements

- Bash 4.0+
- git
- grep with `-E` (extended regex) support

No external dependencies. Works on Linux and macOS.

## License

MIT License. See [LICENSE](../LICENSE) for details.

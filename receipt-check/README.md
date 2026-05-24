# receipt-check

Tier the supporting evidence for an AI procurement claim *before* committing an irreversible decision on top of it.

Companion script for [Bashmatica! #16: They Fired The Net.](https://www.bashmatica.com/archive/016-they-fired-the-net/).

## The problem

A vendor's productivity claim and a production deployment of that same claim are not the same artifact. The first is sales material. The second is what actually happens when you wire it into your operation. When companies justify irreversible decisions (workforce cuts, contract cancellations, infrastructure rip-outs) on the productivity case, they often cite the first artifact and skip the second, even when the second already exists somewhere public.

`receipt-check` reads a JSON file of procurement claims and tiers each one by the kind of evidence backing it:

- **vendor_demo** — vendor's marketing site, sales deck, demo video
- **vendor_case_study** — vendor-published success story with metrics and a willing customer
- **vendor_funded_study** — third-party author, vendor money
- **independent_study** — third-party author, independent funding
- **our_pilot** — production data from your own pilot at smaller-than-final scale

The verdict is gated against the *reversibility* of the decision being made on top of the claim. An irreversible decision needs at least an `independent_study` to pass, and ideally `our_pilot` at your scale. A reversible feature-flag flip can ride lighter evidence. The verdict matrix lives in `receipt-check.sh` and is short enough to read in one sitting.

The output is a per-claim scorecard you commit alongside the procurement decision so the audit trail lives in the same repo as the decision.

## Install

```bash
git clone https://github.com/bobbyrgoldsmith/bashmatica-scripts.git
cd bashmatica-scripts/receipt-check
chmod +x receipt-check.sh
```

Hard dependency: `jq` (`brew install jq`).

Targets bash 3.2+ — macOS-compatible out of the box.

## Usage

### Run against a claims file

```bash
./receipt-check.sh --claims path/to/procurement-claims.json
```

The file must have shape `{ "claims": [ { "claim": ..., "source_type": ..., ... } ] }`.

### Run against a flat JSON array

```bash
./receipt-check.sh --list path/to/claims.json
```

Where `claims.json` is `[ { "claim": ..., ... }, ... ]` directly.

### Run against the bundled example

```bash
./receipt-check.sh --example
```

### Output formats

```bash
./receipt-check.sh --claims c.json --format markdown   # default
./receipt-check.sh --claims c.json --format json
./receipt-check.sh --claims c.json --format csv
```

### Decision gating

```bash
./receipt-check.sh --claims c.json --strict
```

Exits non-zero on any `fail` or `incomplete` verdict. Wire this into a CI step on a procurement-decisions repo, or run it as a precondition before a workforce-impacting decision is signed.

`--ci` is an alias for `--strict --format markdown`.

### Authoring claims in YAML

Claims read more naturally in YAML than in JSON. Author in YAML and pipe through `yq` for conversion:

```bash
yq -o=json claims.yaml | ./receipt-check.sh --list /dev/stdin --strict
```

## Claim object schema

```json
{
  "claim": "47% faster ticket triage",
  "vendor": "Acme Triage AI",
  "source_url": "https://acmeai.com/case-studies/global-bank-pilot",
  "source_type": "vendor_case_study",
  "sample_size": 23,
  "timeframe_weeks": 4,
  "deployment_scale": "one 5-person team",
  "regression_rate": "not disclosed",
  "our_deployment_scale": "support org of 2400",
  "decision_reversibility": "irreversible",
  "decision_description": "elimination of tier-1 support layer"
}
```

### Required fields

- Always required: `claim`, `source_type`, `decision_reversibility`
- Required unless `source_type == "vendor_demo"`: `sample_size`, `timeframe_weeks`, `deployment_scale`

`vendor_demo` is exempt from the production-data fields because there isn't any to cite. A demo is a demo. The exemption is what flags vendor_demo as the weakest tier in the verdict matrix.

### Verdict matrix

| Reversibility   | < independent_study | < our_pilot         | our_pilot |
|-----------------|---------------------|---------------------|-----------|
| reversible      | pass                | pass                | pass      |
| semi_reversible | warn                | pass                | pass      |
| irreversible    | **fail**            | warn                | pass      |

Missing required fields or unknown enum values produce `incomplete` regardless of reversibility.

## Suggested workflow

The Bashmatica #16 "Quick Wins" path:

1. **(15 min)** List every AI productivity claim currently being cited in a planning meeting, procurement deck, or RFP response inside your org. Write each as a `claim` row.
2. **(1 hour)** Run `receipt-check` over the list. Anything failing or incomplete is a claim that should not be the load-bearing input to an irreversible decision. Surface the gap to the decision owner.
3. **(half day)** Bake `receipt-check --strict` into the workflow that approves AI-procurement-driven workforce or contract decisions. Make the audit trail (the claims file) a required artifact of the approval. Run a reversible pilot at your scale before committing to anything `irreversible`.

## Classification approach

The verdict matrix is intentionally short and conservative. The four guiding principles:

1. **Reversibility sets the evidence bar, not the claim's size.** A 5% productivity claim backed by an independent study at your scale beats a 70% claim backed by a vendor demo. The script treats them accordingly.
2. **Vendor-controlled evidence is one tier.** Vendor demos, vendor case studies, and vendor-funded studies all share a structural property: the vendor controlled selection, framing, or funding. They differ in degree, not in kind, and the matrix collapses them into a shared "below independent" bucket for irreversible decisions.
3. **Production data at your scale is the only thing that earns a pass on the hardest decisions.** This is the `our_pilot` tier. A pilot you ran in your own environment, against your actual workload, with your actual people, is the only evidence type that survives the gap between vendor demo conditions and your production conditions.
4. **Unknown source types are not zero-evidence. They are incomplete.** The matrix doesn't try to guess. If the operator can't classify the evidence, the procurement decision shouldn't proceed.

## Related scripts in this repo

- [`blast-radius-guard`](../blast-radius-guard/) — git-diff scanner for destructive shell patterns at commit time (Bashmatica #6).
- [`behavior-canary`](../behavior-canary/) — pre-deploy red-team prompt runner that diffs agent responses against a known-good baseline (Bashmatica #14).
- [`agent-net`](../agent-net/) — classify an agent's tool manifest by reversibility tier before deploy (Bashmatica #15).

The four together form a lifecycle: `receipt-check` watches the procurement decision, `blast-radius-guard` watches what humans+AI write into source, `behavior-canary` watches how the agent responds, and `agent-net` watches what the agent's tools are allowed to do.

## License

MIT. See repo root.

## Hand-raiser

Reply to the Bashmatica #16 thread with `RECEIPTS` to receive the script + an example claims file + the verdict matrix in a single DM.

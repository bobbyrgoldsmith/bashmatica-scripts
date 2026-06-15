#!/usr/bin/env bash
#
# failover-check.sh — Refuse a single-homed LLM provider config before it ships,
# so a forced model shutdown can't take your whole product down with it.
#
# In June 2026 a government export-control order pulled Anthropic's Fable 5 and
# Mythos 5 for every customer worldwide, about ninety minutes after the letter
# arrived. The lesson for builders wasn't about that one model. It was that model
# access is a revocable license, not an asset you own, and that provider-level
# availability is a different risk from model capability. The team that had a
# second provider wired in switched routes and kept serving. The team whose
# "fallback" was the same vendor on a different endpoint (the API, then Bedrock)
# went down twice, because a provider-level block hits every channel that vendor
# runs.
#
# failover-check reads a routing manifest (llm-providers.yaml or any equivalent)
# and refuses a config that can't survive losing its primary provider. Five
# checks:
#
#   PRIMARY      — a primary route is declared and resolves to provider/model.
#                  No primary, nothing to reason about. FAIL.
#   FAILOVER     — at least one fallback resolves to a DIFFERENT provider than the
#                  primary. A fallback on the same vendor (Anthropic API then
#                  Bedrock) is not a fallback: a provider-level shutdown takes
#                  both. No fallback, or every fallback on the primary's vendor,
#                  means a single point of failure. FAIL.
#   CREDS        — every provider in the routing chain has a provider block and
#                  declares an api_key_env. A fallback you can't authenticate is
#                  not a fallback. FAIL.
#   KEY-PRESENT  — each declared api_key_env is actually set and non-empty in the
#                  current environment. A key named in config but missing at
#                  runtime fails over to nothing. WARN (FAIL under --strict).
#   ORPHAN       — a provider block defined but never referenced by any route.
#                  Usually a typo'd route or a configured alternative you forgot
#                  to wire in, which is exactly the alternative that would have
#                  saved you. WARN (FAIL under --strict).
#
# A manifest that clears all five can lose its primary provider and keep serving.
# One that doesn't is a single vendor's outage away from being your outage.
#
# Usage:
#   ./failover-check.sh --config <manifest.yaml>
#   ./failover-check.sh --config ./llm-providers.yaml
#   ./failover-check.sh --config ./llm-providers.yaml --strict   # WARNs also fail
#   ./failover-check.sh --example
#
# Options:
#   --config <file>   The routing manifest to validate (required, unless
#                     --example). Expects an llm-providers.yaml shape: a
#                     `routing:` block with `primary:` and a `fallbacks:` list,
#                     and a `providers:` mapping, each with `api_key_env:`.
#                     Routes are written provider/model (e.g. anthropic/claude-fable-5).
#   --strict          KEY-PRESENT and ORPHAN warnings also refuse the manifest.
#   --example         Run against the bundled sample manifest (a primary with only
#                     a same-vendor fallback, and an unused cross-vendor provider
#                     sitting right there).
#
# Exit codes:
#   0 — CLEAN. The config survives losing its primary provider. (Possibly with warnings.)
#   1 — NOT CLEAN. At least one check refused it.
#   2 — usage / input error.
#
# Requires: bash 3.2+, awk, grep. Fact extraction is a pure-awk parser for the
# regular llm-providers.yaml shape, so there is no hard YAML dependency. If `yq`
# happens to be installed it is used only to reject a syntactically broken
# manifest up front; nothing else changes.

set -uo pipefail

usage() {
  awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
  exit "${1:-2}"
}

# ----------------------------------------------------------------------
# Parse args
# ----------------------------------------------------------------------
CONFIG=""
STRICT=0
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)  CONFIG="${2:-}"; shift 2 ;;
    --strict)  STRICT=1; shift ;;
    --example)
      CONFIG="$SELF_DIR/examples/llm-providers.yaml"
      shift ;;
    -h|--help) usage 0 ;;
    *)         echo "Unknown option: $1" >&2; usage 2 ;;
  esac
done

if [[ -z "$CONFIG" ]]; then
  echo "Error: no --config manifest given" >&2
  usage 2
fi
if [[ ! -f "$CONFIG" ]]; then
  echo "Error: config not found: $CONFIG" >&2
  exit 2
fi

# ----------------------------------------------------------------------
# Parse the manifest into flat, greppable records:
#   PRIMARY <provider> <model>
#   FALLBACK <provider> <model>
#   PROVIDER <name>
#   PROVKEY <name> <ENV_VAR>
#
# A pure-awk parser handles the regular two-space-indented llm-providers.yaml
# shape. Routes are split on the first slash into provider/model.
# ----------------------------------------------------------------------
parse_awk() {
  awk '
    function indent(line,   i) { i = 0; while (substr(line, i+1, 1) == " ") i++; return i }
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function strip_q(s) { sub(/^["'\'']/, "", s); sub(/["'\'']$/, "", s); return s }
    function emit_route(tag, s,   slash, p, m) {
      slash = index(s, "/")
      if (slash == 0) { p = s; m = "" }
      else { p = substr(s, 1, slash - 1); m = substr(s, slash + 1) }
      print tag " " trim(p) " " trim(m)
    }

    BEGIN { section=""; in_fallbacks=0; ind_fb=-1; ind_providers=-1; cur_provider="" }

    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }

    {
      ind = indent($0)
      line = trim($0)
      key = line; sub(/:.*/, "", key)
      val = ""
      if (line ~ /:[[:space:]]*[^[:space:]]/) {
        val = line; sub(/^[^:]*:[[:space:]]*/, "", val)
        if (val !~ /^["'\'']/) sub(/[[:space:]]+#.*$/, "", val)
        val = strip_q(trim(val))
      }
    }

    # top-level section markers (indent 0)
    ind == 0 {
      section = key
      in_fallbacks=0; ind_fb=-1; cur_provider=""
      if (section == "providers") ind_providers = -1
      next
    }

    # ---------- routing: ----------
    section == "routing" {
      if (key == "primary" && val != "") { emit_route("PRIMARY", val); in_fallbacks=0; next }
      if (key == "fallbacks") { in_fallbacks=1; ind_fb=-1; next }
      if (in_fallbacks && line ~ /^-[[:space:]]*/) {
        item = line; sub(/^-[[:space:]]*/, "", item)
        if (item !~ /^["'\'']/) sub(/[[:space:]]+#.*$/, "", item)
        item = strip_q(trim(item))
        if (item != "") emit_route("FALLBACK", item)
        next
      }
      # any non-list key ends the fallbacks list
      if (line !~ /^-/) in_fallbacks=0
      next
    }

    # ---------- providers: ----------
    section == "providers" {
      if (ind_providers < 0 && key != "" && val == "") ind_providers = ind
      if (ind == ind_providers && key != "") { cur_provider = key; print "PROVIDER " cur_provider; next }
      if (cur_provider != "" && key == "api_key_env" && val != "") {
        print "PROVKEY " cur_provider " " val; next
      }
      next
    }
  ' "$1"
}

if command -v yq >/dev/null 2>&1; then
  if ! yq -e '.' "$CONFIG" >/dev/null 2>&1; then
    echo "Error: $CONFIG is not valid YAML (yq could not parse it)" >&2
    exit 2
  fi
fi
RECORDS="$(parse_awk "$CONFIG")"

PRIMARY_PROV="$(printf '%s\n' "$RECORDS" | awk '$1=="PRIMARY"{print $2; exit}')"
PRIMARY_MODEL="$(printf '%s\n' "$RECORDS" | awk '$1=="PRIMARY"{print $3; exit}')"
FALLBACK_PROVS="$(printf '%s\n' "$RECORDS" | awk '$1=="FALLBACK"{print $2}')"
PROVIDERS="$(printf '%s\n' "$RECORDS" | awk '$1=="PROVIDER"{print $2}')"

FAIL=0
WARN=0

# ----------------------------------------------------------------------
# Check 1 — PRIMARY: a primary route is declared and resolves to provider/model.
# ----------------------------------------------------------------------
if [[ -z "$PRIMARY_PROV" || -z "$PRIMARY_MODEL" ]]; then
  echo "PRIMARY     no primary route declared (expected routing.primary: provider/model)  FAIL"
  FAIL=$((FAIL + 1))
else
  echo "PRIMARY     $PRIMARY_PROV/$PRIMARY_MODEL  OK"
fi

# The set of providers actually in the routing chain (primary + fallbacks).
ROUTED_PROVS="$(printf '%s\n%s\n' "$PRIMARY_PROV" "$FALLBACK_PROVS" | awk 'NF' | sort -u)"

# ----------------------------------------------------------------------
# Check 2 — FAILOVER: at least one fallback on a DIFFERENT provider than primary.
# ----------------------------------------------------------------------
CROSS_VENDOR=""
for fp in $FALLBACK_PROVS; do
  if [[ -n "$fp" && "$fp" != "$PRIMARY_PROV" ]]; then CROSS_VENDOR="$fp"; break; fi
done
if [[ -z "$FALLBACK_PROVS" ]]; then
  echo "FAILOVER    no fallback route declared; primary is a single point of failure  FAIL"
  FAIL=$((FAIL + 1))
elif [[ -z "$CROSS_VENDOR" ]]; then
  echo "FAILOVER    every fallback shares the primary's vendor ($PRIMARY_PROV); a provider-level block takes them all  FAIL"
  FAIL=$((FAIL + 1))
else
  echo "FAILOVER    cross-vendor fallback present ($CROSS_VENDOR)  OK"
fi

# ----------------------------------------------------------------------
# Check 3 — CREDS: every routed provider has a block and declares an api_key_env.
# ----------------------------------------------------------------------
NO_CREDS=""
for p in $ROUTED_PROVS; do
  if ! printf '%s\n' "$PROVIDERS" | grep -qx "$p"; then
    NO_CREDS="$NO_CREDS $p(no-block)"
  elif ! printf '%s\n' "$RECORDS" | grep -qE "^PROVKEY $p "; then
    NO_CREDS="$NO_CREDS $p(no-api_key_env)"
  fi
done
NO_CREDS="$(echo "$NO_CREDS" | xargs 2>/dev/null || true)"
if [[ -n "$NO_CREDS" ]]; then
  echo "CREDS       routed provider missing credentials path: $NO_CREDS  FAIL"
  FAIL=$((FAIL + 1))
else
  echo "CREDS       every routed provider declares an api_key_env  OK"
fi

# ----------------------------------------------------------------------
# Check 4 — KEY-PRESENT: each declared api_key_env is set and non-empty in env.
# ----------------------------------------------------------------------
MISSING_ENV=""
while IFS= read -r rec; do
  [[ -z "$rec" ]] && continue
  prov="$(echo "$rec" | awk '{print $2}')"
  envvar="$(echo "$rec" | awk '{print $3}')"
  # only check providers that are actually in the routing chain
  printf '%s\n' "$ROUTED_PROVS" | grep -qx "$prov" || continue
  if [[ -z "${!envvar:-}" ]]; then
    MISSING_ENV="$MISSING_ENV $envvar($prov)"
  fi
done <<EOF
$(printf '%s\n' "$RECORDS" | awk '$1=="PROVKEY"')
EOF
MISSING_ENV="$(echo "$MISSING_ENV" | xargs 2>/dev/null || true)"
if [[ -n "$MISSING_ENV" ]]; then
  if [[ "$STRICT" -eq 1 ]]; then
    echo "KEY-PRESENT api_key_env unset or empty in environment: $MISSING_ENV  FAIL"
    FAIL=$((FAIL + 1))
  else
    echo "KEY-PRESENT api_key_env unset or empty in environment: $MISSING_ENV  WARN"
    WARN=$((WARN + 1))
  fi
else
  echo "KEY-PRESENT every routed api_key_env is set in the environment  OK"
fi

# ----------------------------------------------------------------------
# Check 5 — ORPHAN: a provider block defined but never referenced by any route.
# ----------------------------------------------------------------------
ORPHAN=""
for p in $PROVIDERS; do
  printf '%s\n' "$ROUTED_PROVS" | grep -qx "$p" || ORPHAN="$ORPHAN $p"
done
ORPHAN="$(echo "$ORPHAN" | xargs 2>/dev/null || true)"
if [[ -n "$ORPHAN" ]]; then
  if [[ "$STRICT" -eq 1 ]]; then
    echo "ORPHAN      provider block defined but never routed: $ORPHAN  FAIL"
    FAIL=$((FAIL + 1))
  else
    echo "ORPHAN      provider block defined but never routed: $ORPHAN  WARN"
    WARN=$((WARN + 1))
  fi
else
  echo "ORPHAN      every defined provider is referenced by a route  OK"
fi

# ----------------------------------------------------------------------
# Verdict
# ----------------------------------------------------------------------
echo
if [[ "$FAIL" -gt 0 ]]; then
  echo "Verdict: NOT CLEAN ($FAIL refusal(s), $WARN warning(s))"
  exit 1
fi
if [[ "$WARN" -gt 0 ]]; then
  echo "Verdict: CLEAN WITH WARNINGS ($WARN warning(s) — survives a primary outage, but has gaps)"
  exit 0
fi
echo "Verdict: CLEAN"
exit 0

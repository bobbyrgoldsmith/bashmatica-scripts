#!/usr/bin/env bash
# egress-fence: run a command as an unprivileged user whose outbound traffic is
# limited, in the kernel, to the hosts you name. Everything else is logged,
# counted, and refused. Fails closed: if the fence can't be built, nothing runs.
#
#   sudo egress-fence -a host1,host2[,...] [-u user] [--strict] -- <command> [args]
#
#   -a, --allow   comma-separated hostnames or IPv4 CIDRs the command may reach
#   -u, --user    unprivileged user to run as (default: fenced; created if absent)
#   --strict      exit 5 if any packet was refused, whatever the command returned
#
# Exit: the command's exit code; 2 bad usage; 3 not root or tools missing;
#       4 an allowlist entry did not resolve; 5 refusals under --strict.
set -euo pipefail

ALLOW=""; FENCED_USER="fenced"; STRICT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a|--allow) ALLOW="$2"; shift 2 ;;
    -u|--user)  FENCED_USER="$2"; shift 2 ;;
    --strict)   STRICT=1; shift ;;
    --)         shift; break ;;
    *) echo "egress-fence: unknown option $1" >&2; exit 2 ;;
  esac
done
[[ $# -gt 0 && -n "$ALLOW" ]] || { echo "usage: sudo egress-fence -a host[,host] [-u user] [--strict] -- cmd [args]" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "egress-fence: needs root to write rules (it drops root before your command runs)" >&2; exit 3; }
for t in iptables setpriv getent; do
  command -v "$t" >/dev/null || { echo "egress-fence: $t not found" >&2; exit 3; }
done

id "$FENCED_USER" >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin "$FENCED_USER"
UID_N=$(id -u "$FENCED_USER")
CHAIN="EGRESS_FENCE_$UID_N"

# Resolve the allowlist once, before the fence goes up. A name that fails to resolve fails the run.
ADDRS=()
IFS=',' read -ra HOSTS <<< "$ALLOW"
for h in "${HOSTS[@]}"; do
  if [[ "$h" =~ ^[0-9.]+(/[0-9]+)?$ ]]; then ADDRS+=("$h"); continue; fi
  mapfile -t got < <(getent ahostsv4 "$h" | awk '{print $1}' | sort -u)
  [[ ${#got[@]} -gt 0 ]] || { echo "egress-fence: cannot resolve $h" >&2; exit 4; }
  ADDRS+=("${got[@]}")
done
mapfile -t RESOLVERS < <(awk '/^nameserver/ {print $2}' /etc/resolv.conf)

teardown() {
  iptables -D OUTPUT -m owner --uid-owner "$UID_N" -j "$CHAIN" 2>/dev/null || true
  iptables -F "$CHAIN" 2>/dev/null || true
  iptables -X "$CHAIN" 2>/dev/null || true
  command -v ip6tables >/dev/null && ip6tables -D OUTPUT -m owner --uid-owner "$UID_N" ! -o lo -j REJECT 2>/dev/null || true
}
trap teardown EXIT
teardown   # clear anything a crashed run left behind

iptables -N "$CHAIN"
iptables -A "$CHAIN" -o lo -j ACCEPT
iptables -A "$CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
for r in "${RESOLVERS[@]}"; do
  iptables -A "$CHAIN" -d "$r" -p udp --dport 53 -j ACCEPT
  iptables -A "$CHAIN" -d "$r" -p tcp --dport 53 -j ACCEPT
done
for a in "${ADDRS[@]}"; do iptables -A "$CHAIN" -d "$a" -j ACCEPT; done
iptables -A "$CHAIN" -m limit --limit 10/min -j LOG --log-prefix "EGRESS_FENCE REFUSED uid=$UID_N " --log-level 4
iptables -A "$CHAIN" -j REJECT --reject-with icmp-admin-prohibited
iptables -I OUTPUT 1 -m owner --uid-owner "$UID_N" -j "$CHAIN"
# The allowlist is IPv4; refuse all IPv6 from the fenced user rather than leave a second door.
command -v ip6tables >/dev/null && ip6tables -I OUTPUT 1 -m owner --uid-owner "$UID_N" ! -o lo -j REJECT

echo "egress-fence: uid=$UID_N allow=${ADDRS[*]} resolvers=${RESOLVERS[*]:-none}" >&2
set +e
setpriv --reuid="$FENCED_USER" --regid="$FENCED_USER" --init-groups -- "$@"
RC=$?
set -e

REFUSED=$(iptables -L "$CHAIN" -v -x -n | awk '$3 == "REJECT" {print $1}')
echo "egress-fence: command exited $RC; refused packets: ${REFUSED:-0}" >&2
[[ $STRICT -eq 1 && ${REFUSED:-0} -gt 0 ]] && exit 5
exit "$RC"

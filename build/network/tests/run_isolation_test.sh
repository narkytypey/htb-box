#!/bin/bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# iptables rule manipulation and `ip netns` both require root.
[ "$(id -u)" -eq 0 ] || die "run this test as root -- it manipulates iptables and creates network namespaces"

cd "$(dirname "$0")/.." || exit 1
source config.env || exit 1

FAKE_INTERNAL_AD_IP="172.28.0.99"
FAKE_AD_VLAN_IP="10.10.20.250"
FAKE_VPN_IP="10.10.14.99"
LISTEN_PORT=8445

# Prefix lengths come from config.env's own CIDRs rather than being
# hardcoded, so a subnet-width change there (e.g. AD_VLAN_SUBNET resized)
# doesn't silently desync this test's netns addressing from reality.
INTERNAL_AD_PREFIX="${INTERNAL_AD_SUBNET#*/}"
AD_VLAN_PREFIX="${AD_VLAN_SUBNET#*/}"
VPN_CLIENT_PREFIX="${VPN_CLIENT_SUBNET#*/}"

ip_to_int() {
  local a b c d
  IFS='.' read -r a b c d <<< "$1"
  echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

# config.env's own top-of-file comment instructs replacing VPN_CLIENT_SUBNET
# with the real HTB player range before deployment. If that (or either other
# subnet) is ever resized/moved without updating the FAKE_* constants below
# to match, the test would silently exercise the wrong address space instead
# of failing loudly -- so assert containment up front and name config.env as
# the thing to reconcile.
assert_ip_in_subnet() {
  local ip="$1" cidr="$2" label="$3"
  local net="${cidr%/*}" plen="${cidr#*/}"
  local ip_int net_int mask
  ip_int="$(ip_to_int "$ip")"
  net_int="$(ip_to_int "$net")"
  mask=$(( (0xFFFFFFFF << (32 - plen)) & 0xFFFFFFFF ))
  if [ $(( ip_int & mask )) -ne $(( net_int & mask )) ]; then
    die "$label: $ip no longer falls inside $cidr -- config.env's subnet changed without updating this test's FAKE_* constants to match"
  fi
}

assert_ip_in_subnet "$FAKE_INTERNAL_AD_IP" "$INTERNAL_AD_SUBNET" "FAKE_INTERNAL_AD_IP/INTERNAL_AD_SUBNET"
assert_ip_in_subnet "$FAKE_AD_VLAN_IP" "$AD_VLAN_SUBNET" "FAKE_AD_VLAN_IP/AD_VLAN_SUBNET"
assert_ip_in_subnet "$FAKE_VPN_IP" "$VPN_CLIENT_SUBNET" "FAKE_VPN_IP/VPN_CLIENT_SUBNET"

# Set before any state-changing call so the EXIT trap can safely reference it
# even if we die partway through setup. Under `set -u`, `kill "$NC_PID"` on a
# still-unset variable would blow up the trap itself -- `set +e` inside
# cleanup() suppresses command failures, not unbound-variable errors.
NC_PID=""

reset_sim_state() {
  # Tolerate leftovers from a previous run of this script that was killed
  # before its own EXIT trap could run (e.g. Ctrl-C mid-test). This runs
  # before `trap cleanup EXIT` is installed below and only ever touches the
  # sim netns/veths -- never the iptables pivot chain -- so a prior run's
  # abandoned fixtures get cleared with no risk of this pre-flight step
  # tearing down production enforcement before setup has even begun.
  #
  # Known gap (documented, not fixed -- a real fix needs ownership tracking,
  # e.g. a marker file, beyond what this test's plan asks for): this does
  # NOT clean up a leftover DONERUP_AD_PIVOT chain from a prior run that was
  # SIGKILLed (not just Ctrl-C'd) before its own EXIT trap could fire. If
  # that prior run had pivot_preexisted=0 (it installed the chain itself)
  # and was killed too hard for the trap to run, the chain survives, and
  # this run's own preexistence probe below will then see it, classify it
  # as production, and faithfully preserve/restore it forever. Fail-closed
  # and harmless in content (it's the same rules this script would have
  # installed anyway) -- but the chain can outlive every run that created it.
  ip netns del internal-ad-sim 2>/dev/null || true
  ip netns del ad-vlan-sim 2>/dev/null || true
  ip netns del vpn-sim 2>/dev/null || true
  ip link del veth-iad-h 2>/dev/null || true
  ip link del veth-adv-h 2>/dev/null || true
  ip link del veth-vpn-h 2>/dev/null || true
}
reset_sim_state

# Was DONERUP_AD_PIVOT already installed before this script touched
# anything? If so, it's the deployed production enforcement from
# donerup-ad-pivot.service, not a fixture this test owns, and cleanup()
# below must restore it rather than delete it.
pivot_preexisted=0
iptables -n -L DONERUP_AD_PIVOT >/dev/null 2>&1 && pivot_preexisted=1

cleanup() {
  set +e
  [ -n "$NC_PID" ] && kill "$NC_PID" 2>/dev/null
  # Deleting a netns already destroys its veth peer; these host-side
  # `ip link del` calls are belt-and-braces for a namespace delete that
  # failed partway, not load-bearing on the normal path.
  ip netns del internal-ad-sim 2>/dev/null
  ip netns del ad-vlan-sim 2>/dev/null
  ip netns del vpn-sim 2>/dev/null
  ip link del veth-iad-h 2>/dev/null
  ip link del veth-adv-h 2>/dev/null
  ip link del veth-vpn-h 2>/dev/null

  if [ "$pivot_preexisted" = "1" ]; then
    # DONERUP_AD_PIVOT (its DOCKER-USER hook, its NAT rule) already existed
    # before this script ran -- this is the live, deployed enforcement, not
    # a test fixture, and must not end up deleted just because this test
    # ran (or failed) once. setup-ad-pivot.sh is idempotent, so re-running
    # it restores exactly what was already there, on every exit path,
    # including every `die`/`exit 1` above. Check its exit status here (and
    # keep stderr, unlike stdout) -- a silently-discarded restore failure
    # would leave the host with no isolation and no indication of it,
    # which is the exact failure this whole branch exists to prevent.
    if ! ./setup-ad-pivot.sh >/dev/null; then
      echo "CRITICAL: failed to restore the pre-existing DONERUP_AD_PIVOT enforcement -- this host currently has NO AD isolation. Re-run setup-ad-pivot.sh (or 'systemctl restart donerup-ad-pivot') before trusting this box." >&2
    fi
  else
    # Nothing pre-existed: this script installed the chain itself, so it
    # is the one responsible for removing it again. Never remove the
    # FORWARD -> DOCKER-USER jump itself here: setup-ad-pivot.sh creates
    # that jump defensively when Docker hasn't installed it yet, so it
    # isn't reliably "Docker's own" to own or disown -- but whichever run
    # created it, this host's container networking depends on it existing,
    # so it stays regardless.
    iptables -D DOCKER-USER -j DONERUP_AD_PIVOT 2>/dev/null
    iptables -F DONERUP_AD_PIVOT 2>/dev/null
    iptables -X DONERUP_AD_PIVOT 2>/dev/null
    iptables -t nat -D POSTROUTING -s "$INTERNAL_AD_SUBNET" -d "$AD_VLAN_SUBNET" -j MASQUERADE 2>/dev/null
  fi
}
trap cleanup EXIT

check_host_ip_available() {
  # Note: a plain multi-stage pipeline ending in `grep -q` can take SIGPIPE
  # on early match while upstream is still writing -- under `pipefail` that
  # reads as "not found" and silently disables this guard on a wide enough
  # `ip -o addr show` listing. `ip ... show to X/32` avoids the pipeline
  # (and the unanchored-substring risk of `grep -qx` on top of it) entirely.
  #
  # Residual gap (documented, not fixed -- would need a new `ip route get`
  # assertion beyond what this test's plan asks for): this checks whether
  # $ip is *assigned* to an interface, not whether the *route* to its
  # subnet already goes somewhere else. A pre-existing 10.10.20.0/24 route
  # via another device, with 10.10.20.1 itself unassigned, would pass this
  # guard and the sim could still misroute.
  local ip="$1"
  if [ -n "$(ip -o addr show to "$ip/32")" ]; then
    if [ "$ip" = "$INTERNAL_AD_GATEWAY_IP" ]; then
      die "host address $ip is already assigned -- the internal-ad Docker bridge is live. Run 'docker compose down' first, then re-run this test."
    elif [ "$ip" = "$AD_VLAN_HOST_IP" ]; then
      die "host address $ip is already assigned -- adlab0 has been provisioned (Plan 3 has run). This pre-DC namespace test has served its purpose; use Plan 4's real-pivot replay against the live DC instead."
    else
      die "host address $ip is already assigned to another interface on this host -- bring down whatever owns it before running this test, then re-run"
    fi
  fi
}

make_netns() {
  local ns="$1" veth_h="$2" veth_ns="$3" ip_addr="$4" prefix="$5" want_default_route="${6:-yes}"
  local host_ip="${ip_addr%.*}.1"

  check_host_ip_available "$host_ip"

  ip netns add "$ns" || die "make_netns($ns): failed to create the network namespace"
  ip link add "$veth_h" type veth peer name "$veth_ns" || die "make_netns($ns): failed to create veth pair $veth_h/$veth_ns"
  ip link set "$veth_ns" netns "$ns" || die "make_netns($ns): failed to move $veth_ns into the namespace"
  ip addr add "${host_ip}/${prefix}" dev "$veth_h" || die "make_netns($ns): failed to address $veth_h as ${host_ip}/${prefix}"
  ip link set "$veth_h" up || die "make_netns($ns): failed to bring $veth_h up"
  ip netns exec "$ns" ip addr add "${ip_addr}/${prefix}" dev "$veth_ns" || die "make_netns($ns): failed to address $veth_ns as ${ip_addr}/${prefix}"
  ip netns exec "$ns" ip link set "$veth_ns" up || die "make_netns($ns): failed to bring $veth_ns up"
  ip netns exec "$ns" ip link set lo up || die "make_netns($ns): failed to bring up loopback"
  if [ "$want_default_route" = "yes" ]; then
    ip netns exec "$ns" ip route add default via "$host_ip" || die "make_netns($ns): failed to add default route via $host_ip"
  fi
}

make_netns internal-ad-sim veth-iad-h veth-iad-ns "$FAKE_INTERNAL_AD_IP" "$INTERNAL_AD_PREFIX"
# No default route here, deliberately: production's DC has no route back to
# 172.28.0.0/24, so the only way a reply reaches it is via the internal-ad ->
# AD-VLAN MASQUERADE rewriting the source to an address on this subnet
# (on-link, needs no gateway). If that NAT rule were ever missing, the
# on-link-only route table below leaves this namespace with no route back to
# the un-NATed 172.28.0.99, so check 1 fails instead of passing on a
# technicality that only works because the sim gave the DC a route production
# doesn't have.
make_netns ad-vlan-sim veth-adv-h veth-adv-ns "$FAKE_AD_VLAN_IP" "$AD_VLAN_PREFIX" no
make_netns vpn-sim veth-vpn-h veth-vpn-ns "$FAKE_VPN_IP" "$VPN_CLIENT_PREFIX"

./setup-ad-pivot.sh || die "setup-ad-pivot.sh failed -- aborting before running isolation checks against a possibly partial rule set"

rule_hits() {
  # Packet counter for the DONERUP_AD_PIVOT rule matching this exact
  # target/source/destination triple -- matched by source/destination (the
  # same values setup-ad-pivot.sh installs each rule with), not by line
  # number, since rule order in the chain isn't part of the contract being
  # tested. Shared by both checks below.
  local target="$1" src="$2" dst="$3" hits
  hits="$(iptables -n -v -x -L DONERUP_AD_PIVOT | awk -v t="$target" -v s="$src" -v d="$dst" \
    '$1 ~ /^[0-9]+$/ && $3 == t && $8 == s && $9 == d {print $1; exit}')"
  echo "${hits:-0}"
}

wait_for_listener() {
  local ns="$1" port="$2" i
  for i in $(seq 1 20); do
    if ip netns exec "$ns" ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${port}\$"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# This host's `nc` is OpenBSD netcat (Debian patchlevel 1.238-1). Verified
# empirically: plain `nc -l -p PORT` exits as soon as the first connection
# closes, so the second `nc -zv` below (the VPN check) would connect to
# nothing and report failure regardless of what iptables does -- check 2
# would PASS for the wrong reason. `-k` keeps the listener up across both
# connection attempts.
ip netns exec ad-vlan-sim nc -k -l -p "$LISTEN_PORT" &
NC_PID=$!
wait_for_listener ad-vlan-sim "$LISTEN_PORT" || die "nc listener never bound to port $LISTEN_PORT in ad-vlan-sim"

# Both checks below zero DONERUP_AD_PIVOT's counters immediately before their
# connection attempt and then assert that a *specific* rule is what actually
# counted the packet. A bare pass/fail on the connection alone would not
# prove that:
#   - check 1: setup-ad-pivot.sh runs under `set -euo pipefail` and can die
#     partway through installing rules (e.g. after the VPN DROP rule but
#     before the internal-ad ACCEPT rule) -- caught above by checking its
#     exit status, but belt-and-braces here too. On a host where dockerd has
#     never started, DOCKER-USER wouldn't even be jumped to, and FORWARD's
#     kernel-default policy is ACCEPT -- so the probe could reach the AD
#     VLAN with no ACCEPT rule ever installed: a vacuous pass exercised
#     exactly by this test's own documented use case (verifying before the
#     stack has ever come up).
#   - check 2: Docker sets FORWARD's policy to DROP, so a missing
#     DONERUP_AD_PIVOT chain would still silently swallow the VPN probe --
#     also a vacuous pass, just via the opposite default policy.
iptables -Z DONERUP_AD_PIVOT

echo -n "[check] internal-ad -> AD VLAN reaches through the pivot path... "
internal_ad_connect_succeeded=0
if ip netns exec internal-ad-sim timeout 2 nc -zv "$FAKE_AD_VLAN_IP" "$LISTEN_PORT" 2>&1 | grep -q succeeded; then
  internal_ad_connect_succeeded=1
fi
accept_hits="$(rule_hits ACCEPT "$INTERNAL_AD_SUBNET" "$AD_VLAN_SUBNET")"

if [ "$internal_ad_connect_succeeded" -ne 1 ]; then
  echo "FAIL"
  exit 1
elif [ "$accept_hits" -eq 0 ]; then
  echo "FAIL (connection succeeded, but the internal-ad ACCEPT rule counter is still 0 -- something other than that rule let the packet through, e.g. a permissive FORWARD/DOCKER-USER default from a partially-applied setup-ad-pivot.sh)"
  exit 1
else
  echo "PASS (matched the internal-ad ACCEPT rule, $accept_hits packet(s))"
fi

iptables -Z DONERUP_AD_PIVOT

echo -n "[check] VPN client subnet -> AD VLAN is blocked... "
vpn_connect_succeeded=0
if ip netns exec vpn-sim timeout 2 nc -zv "$FAKE_AD_VLAN_IP" "$LISTEN_PORT" 2>&1 | grep -q succeeded; then
  vpn_connect_succeeded=1
fi
drop_hits="$(rule_hits DROP "$VPN_CLIENT_SUBNET" "$AD_VLAN_SUBNET")"

if [ "$vpn_connect_succeeded" -eq 1 ]; then
  echo "FAIL (VPN subnet reached the AD VLAN directly)"
  exit 1
elif [ "$drop_hits" -eq 0 ]; then
  echo "FAIL (connection did not succeed, but the VPN-subnet DROP rule counter is still 0 -- something other than our rule blocked it, so this proves nothing)"
  exit 1
else
  echo "PASS (blocked by the VPN-subnet DROP rule, matched $drop_hits packet(s))"
fi

echo "ALL ISOLATION CHECKS PASSED"

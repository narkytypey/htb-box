#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
source config.env

sysctl -w net.ipv4.ip_forward=1 >/dev/null

# --- Gateway drift guard -----------------------------------------------
# config.env's INTERNAL_AD_GATEWAY_IP is a hand-verified snapshot of what
# Docker's IPAM assigned to the internal-ad bridge (see the comment in
# config.env). If Docker ever reassigns that gateway (network recreated,
# IPAM pool changed, etc.), the container's `ip route add ... via <ip>`
# from Task 2 would silently install a black-hole route: the kernel only
# checks the address is on-link, not that anything answers, so no error
# surfaces there. This host-side script has real `docker` CLI access, so
# it's the right place to catch the drift -- but only as a LOUD WARNING,
# never a hard failure. At boot, `After=docker.service` only guarantees
# the daemon is up, not that the internal-ad network (created by the
# compose stack) exists yet. Failing here would break reset-resilience.
if command -v docker >/dev/null 2>&1; then
  if docker network inspect internal-ad >/dev/null 2>&1; then
    actual_gateway="$(docker network inspect internal-ad \
      --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || true)"
    if [ -n "$actual_gateway" ] && [ "$actual_gateway" != "$INTERNAL_AD_GATEWAY_IP" ]; then
      echo "WARNING: internal-ad gateway drift detected!" >&2
      echo "WARNING: config.env says INTERNAL_AD_GATEWAY_IP=$INTERNAL_AD_GATEWAY_IP" >&2
      echo "WARNING: docker actually assigned gateway=$actual_gateway" >&2
      echo "WARNING: the web container's route to the AD VLAN may be a black hole -- update config.env" >&2
    fi
  fi
fi
# -------------------------------------------------------------------------

# Idempotency: (re)create our chain clean every run.
iptables -N DONERUP_AD_PIVOT 2>/dev/null || iptables -F DONERUP_AD_PIVOT

# Hook into DOCKER-USER, not FORWARD directly. Docker's own iptables
# reconciliation (e.g. across a daemon restart) may reshuffle rules
# inserted straight into FORWARD, but it never rewrites DOCKER-USER's
# contents -- that chain exists specifically as the stable, documented
# extension point for user rules that must survive Docker's own network
# management (spec section 6.3 reset-resilience). The FORWARD -> DOCKER-USER
# jump carries no interface filter, so it is traversed for ALL forwarded
# traffic -- Docker-managed or not -- including Task 4's non-Docker
# ip-netns veth-pair test traffic.
#
# Ensure DOCKER-USER exists even if Docker hasn't finished its own setup
# yet: After=docker.service only guarantees the daemon has started, not
# that it has installed its chains. Creating it ourselves is harmless --
# Docker only ever ensures the chain exists and never rewrites its
# contents, so there is no conflict if Docker creates/adopts it later.
iptables -N DOCKER-USER 2>/dev/null || true

# Ensure FORWARD actually jumps to DOCKER-USER. Without this, if Docker
# hasn't installed its own jump yet, our rules would sit in a chain that
# nothing traverses -- enforcement silently absent, exactly the class of
# silent failure this whole plan is designed against.
iptables -C FORWARD -j DOCKER-USER 2>/dev/null || iptables -I FORWARD -j DOCKER-USER

iptables -C DOCKER-USER -j DONERUP_AD_PIVOT 2>/dev/null || iptables -I DOCKER-USER -j DONERUP_AD_PIVOT

# 1. Explicit deny: the HTB VPN client subnet never reaches the AD VLAN directly.
iptables -A DONERUP_AD_PIVOT -s "$VPN_CLIENT_SUBNET" -d "$AD_VLAN_SUBNET" -j DROP

# 2. Only the internal-ad bridge (i.e. the web container) may reach the AD VLAN.
iptables -A DONERUP_AD_PIVOT -s "$INTERNAL_AD_SUBNET" -d "$AD_VLAN_SUBNET" -j ACCEPT
iptables -A DONERUP_AD_PIVOT -s "$AD_VLAN_SUBNET" -d "$INTERNAL_AD_SUBNET" -m state --state ESTABLISHED,RELATED -j ACCEPT

# 3. Default deny for anything else addressed to the AD VLAN.
iptables -A DONERUP_AD_PIVOT -d "$AD_VLAN_SUBNET" -j DROP

# 4. NAT internal-ad -> AD VLAN behind the host's AD-VLAN IP, so the DC
#    never needs a route back to the Docker-internal 172.28.0.0/24 range.
iptables -t nat -C POSTROUTING -s "$INTERNAL_AD_SUBNET" -d "$AD_VLAN_SUBNET" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -s "$INTERNAL_AD_SUBNET" -d "$AD_VLAN_SUBNET" -j MASQUERADE

echo "donerup AD pivot rules applied"

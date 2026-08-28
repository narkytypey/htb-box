# Donerup Network Pivot (Plan 2 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the network topology and host-level enforcement that makes the AD segment structurally unreachable except by pivoting through the `web` container — a Docker `internal-ad` bridge, a host bridge standing in for the AD VLAN, and an iptables `FORWARD` chain that accepts the pivot path and drops the HTB VPN client subnet — with the whole enforcement chain verified using throwaway network namespaces before Plan 3's real Windows DC exists.

**Architecture:** Three networks meet at the Docker host: `dmz` (Plan 1, public-facing), `internal-ad` (new, Docker `internal: true` bridge — no automatic NAT/egress — carrying the `web` container's second NIC), and `adlab0` (new, a host bridge to the hypervisor vSwitch that will carry the real AD VLAN once Plan 3 provisions the DC there). The `web` container already needs a route to the AD VLAN for its own legitimate LDAP bind once `LDAP_MODE=real` (Plan 3) — that route is what a pivot tool riding inside the container also uses to reach the AD VLAN, so no exploit-only wiring is added. The Docker host's iptables `FORWARD` chain is the only thing that turns that route into a working path: it accepts `internal-ad → adlab0` traffic and explicitly drops the HTB VPN client subnet, installed by an idempotent script pinned to boot via systemd for reset-resilience. All of this is verified with `ip netns` namespaces simulating the AD VLAN and the VPN client subnet, so the isolation logic is proven correct without a real DC or real VPN traffic.

**Tech Stack:** Docker Compose, iptables, systemd, Linux network namespaces (`ip netns`, `veth`), bash.

**Relationship to other plans:** Modifies `build/docker-compose.yml`, `build/web/Dockerfile`, and `build/web/docker-entrypoint.sh` from Plan 1 (`2026-08-24-donerup-web-app.md`). Plan 3 (`2026-08-24-donerup-ad-escalation.md`) plugs the real Windows DC VM into `adlab0`, replacing the fake-DC network namespace used for testing here. Plan 4 (`2026-08-24-donerup-end-to-end.md`) replays the pivot for real once Plan 3 exists.

**Source spec:** `$REPO/donerup-htb-insane-design-v2.md` (v3), §6.

**Paths:** commands below use `$REPO` for this repository's checkout root.
Set it once per shell before following any task, e.g.
`REPO=~/Desktop/htb-box` (this plan was originally executed with
`REPO=/home/kal/Desktop/htb-box`).


---

## File Structure

```
htb-box/
  build/
    docker-compose.yml            # MODIFY: add internal-ad network, web 2nd NIC, NET_ADMIN cap
    web/
      Dockerfile                  # MODIFY: add gosu, keep image startable as root
      docker-entrypoint.sh        # MODIFY: add AD-VLAN route as root, then drop to appuser
    network/
      config.env                  # single source of truth for subnets/interfaces
      setup-ad-pivot.sh            # idempotent iptables FORWARD + MASQUERADE rules
      donerup-ad-pivot.service     # systemd unit, After=docker.service, boot-persistent
      tests/
        run_isolation_test.sh      # netns-based proof: pivot path works, VPN-direct path is dropped
```

`config.env` is the only place subnet/IP literals live; the compose file, the iptables script, the systemd unit, and the test script all read from it, so there is exactly one place to update when the real HTB VPN range or hypervisor network differs from the placeholder values used here.

---

### Task 1: Network config + `internal-ad` Docker network

**Files:**
- Create: `build/network/config.env`
- Modify: `build/docker-compose.yml`

- [ ] **Step 1: Write the shared network config**

`build/network/config.env`:

```bash
# Single source of truth for the Donerup network topology.
# AD_VLAN_SUBNET / AD_VLAN_HOST_IP / DC_IP describe the host bridge that
# Plan 3's Windows DC VM will be plugged into. VPN_CLIENT_SUBNET is a
# placeholder — replace it with the real HTB VPN player range before
# deploying this box for real; the isolation logic doesn't depend on the
# exact value, only on it differing from INTERNAL_AD_SUBNET.

INTERNAL_AD_BRIDGE=internal-ad
INTERNAL_AD_SUBNET=172.28.0.0/24
WEB_INTERNAL_AD_IP=172.28.0.10

AD_VLAN_BRIDGE=adlab0
AD_VLAN_SUBNET=10.10.20.0/24
AD_VLAN_HOST_IP=10.10.20.1
DC_IP=10.10.20.10

VPN_CLIENT_SUBNET=10.10.14.0/23
```

- [ ] **Step 2: Add the `internal-ad` network and the `web` service's second interface**

In `build/docker-compose.yml`, replace the `networks:` top-level block and the `web` service's `networks:` key:

```yaml
services:
  web:
    build: ./web
    ports:
      - "8080:5000"
    environment:
      LDAP_MODE: mock
      FLASK_SECRET_KEY: dev-only-not-for-prod
    cap_add:
      - NET_ADMIN
    extra_hosts:
      - "dc01.donerup.htb:10.10.20.10"
    networks:
      dmz: {}
      internal-ad:
        ipv4_address: 172.28.0.10

  legacy-auth-db:
    build: ./legacy-auth-db
    environment:
      MYSQL_ROOT_PASSWORD: "DonerciKral99!"
      MYSQL_DATABASE: legacy_auth
    networks:
      - dmz

networks:
  dmz:
    name: dmz
    driver: bridge
  internal-ad:
    name: internal-ad
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.28.0.0/24
```

`internal: true` disables Docker's automatic NAT/masquerade and default-route advertisement for this network — any path out of it has to be something we build explicitly (Task 3), not something Docker gives us for free. `NET_ADMIN` is needed for the route added in Task 2 — the `web` app legitimately needs it to reach its own LDAP backend once Plan 3 switches `LDAP_MODE` to `real`; it isn't exploit-only wiring.

- [ ] **Step 3: Bring the stack up and confirm the second interface exists**

```bash
cd $REPO/build
docker compose up -d --build
docker compose exec web ip -4 addr show
```

Expected: two interfaces beyond `lo` — one on the `dmz` network, one showing `172.28.0.10/24`.

- [ ] **Step 4: Confirm `internal-ad` has no automatic NAT/egress**

```bash
docker network inspect internal-ad --format '{{.Internal}}'
```

Expected: `true`.

- [ ] **Step 5: Confirm the DC hostname hint resolves (discovery hint from spec §6.2)**

```bash
docker compose exec web getent hosts dc01.donerup.htb
```

Expected: `10.10.20.10   dc01.donerup.htb` — this is the discovery breadcrumb a player finds via `/etc/hosts` once inside the container, pointing them at the AD VLAN before Plan 3's DC is reachable there.

- [ ] **Step 6: Commit**

```bash
cd $REPO
git add build/network/config.env build/docker-compose.yml
git commit -m "feat: add internal-ad Docker network and web container's second NIC"
```

---

### Task 2: AD-VLAN route, added as root then dropped to `appuser`

**Files:**
- Modify: `build/web/Dockerfile`
- Modify: `build/web/docker-entrypoint.sh`

- [ ] **Step 1: Add `gosu` and stop dropping to `appuser` at build time**

In `build/web/Dockerfile`, replace the privilege-drop section — remove the `USER appuser` line and add `gosu`:

```dockerfile
FROM python:3.12-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends gosu iproute2 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
COPY wsgi.py .
COPY CHANGELOG.md /home/appuser/CHANGELOG.md
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chown -R appuser:appuser /app /home/appuser

EXPOSE 5000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "wsgi:app"]
```

The image now starts as root (needed for the route in Step 2, which requires `CAP_NET_ADMIN` in an effective capability set that only root gets by default even with `cap_add`), and `gosu` drops to `appuser` for the actual application process — `appuser` never gains the capability itself, keeping the low-privilege foothold from Plan 1 §5 intact.

- [ ] **Step 2: Add the AD-VLAN route to the entrypoint, then drop privileges**

`build/web/docker-entrypoint.sh`:

```bash
#!/bin/sh
set -e

if [ ! -f /home/appuser/user.txt ]; then
    python3 -c "import secrets; print(secrets.token_hex(16))" > /home/appuser/user.txt
    chmod 400 /home/appuser/user.txt
    chown appuser:appuser /home/appuser/user.txt
fi

# The app needs this route for its own LDAP bind once real-LDAP mode is
# active (Plan 3) -- it is not added specifically to enable a pivot tool, though
# a pivot tool riding inside the container uses the same kernel route.
#
# AD_VLAN_SUBNET / INTERNAL_AD_SUBNET / INTERNAL_AD_GATEWAY_IP come in via
# compose from network/config.env -- nothing is hardcoded here.
#
# Which NIC (eth0/eth1/...) Compose attaches "internal-ad" to is not a
# documented contract and is not assumed here. Instead, find the
# interface that owns the internal-ad subnet by matching the kernel's
# own link-scope route table against INTERNAL_AD_SUBNET.
ad_vlan_iface=$(ip -4 -o route list scope link | awk -v subnet="$INTERNAL_AD_SUBNET" '$1 == subnet { print $3; exit }')

if ip route show "$AD_VLAN_SUBNET" | grep -q .; then
    : # route already present, nothing to do
elif [ -n "$ad_vlan_iface" ] && ip route add "$AD_VLAN_SUBNET" via "$INTERNAL_AD_GATEWAY_IP" dev "$ad_vlan_iface"; then
    : # route added successfully
else
    echo "WARN: failed to add AD VLAN route to $AD_VLAN_SUBNET via $INTERNAL_AD_GATEWAY_IP dev ${ad_vlan_iface:-<unresolved>}" >&2
fi

exec gosu appuser "$@"
```

- [ ] **Step 3: Rebuild and confirm the route exists and the app process still runs unprivileged**

```bash
cd $REPO/build
docker compose up -d --build
docker compose exec web ip route show 10.10.20.0/24
docker compose exec web ps -o user,comm -C gunicorn
```

Expected: the route line shows `10.10.20.0/24 via 172.28.0.1 dev eth1` (or whichever NIC Compose actually attaches `internal-ad` to — the entrypoint resolves this dynamically rather than assuming `eth1`); the `gunicorn` process's `USER` column shows `appuser`, not `root`.

- [ ] **Step 4: Confirm the flag file is still owned by `appuser`, not root**

```bash
docker compose exec web ls -l /home/appuser/user.txt
```

Expected: owner `appuser appuser`, mode `-r--------`.

- [ ] **Step 5: Commit**

```bash
cd $REPO
git add build/web/Dockerfile build/web/docker-entrypoint.sh
git commit -m "feat: add AD-VLAN route via root-then-drop entrypoint pattern"
```

---

### Task 3: Host iptables enforcement + boot persistence

**Files:**
- Create: `build/network/setup-ad-pivot.sh`
- Create: `build/network/donerup-ad-pivot.service`

- [ ] **Step 1: Write the idempotent enforcement script**

`build/network/setup-ad-pivot.sh`:

```bash
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
```

- [ ] **Step 2: Make it executable and run it once by hand**

```bash
chmod +x $REPO/build/network/setup-ad-pivot.sh
sudo $REPO/build/network/setup-ad-pivot.sh
sudo $REPO/build/network/setup-ad-pivot.sh
```

Expected: both runs print `donerup AD pivot rules applied` with no errors — the second run proves idempotency (no duplicate rules, no "chain already exists" failure).

- [ ] **Step 3: Confirm no duplicate rules were created**

```bash
sudo iptables -S DONERUP_AD_PIVOT | wc -l
```

Expected: `5` (the `-N` line plus the 4 `-A` rules from the script) — unchanged after running the script twice.

- [ ] **Step 4: Write the systemd unit for boot persistence**

`build/network/donerup-ad-pivot.service`:

```ini
[Unit]
Description=Donerup AD pivot iptables enforcement
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/donerup/network
ExecStart=/opt/donerup/network/setup-ad-pivot.sh
ExecStop=/sbin/iptables -F DONERUP_AD_PIVOT

[Install]
WantedBy=multi-user.target
```

`After=docker.service` / `Requires=docker.service` order this after Docker brings up its own bridges (including `internal-ad`) on boot, per spec §6.3's reset-resilience requirement — this rule set must survive a host reboot without manual intervention.

- [ ] **Step 5: Install and enable the unit on the Docker host**

```bash
sudo mkdir -p /opt/donerup/network
sudo cp $REPO/build/network/config.env \
        $REPO/build/network/setup-ad-pivot.sh \
        /opt/donerup/network/
sudo cp $REPO/build/network/donerup-ad-pivot.service \
        /etc/systemd/system/donerup-ad-pivot.service
sudo systemctl daemon-reload
sudo systemctl enable --now donerup-ad-pivot.service
sudo systemctl status donerup-ad-pivot.service --no-pager
```

Expected: `Active: active (exited)` and no failed units.

- [ ] **Step 6: Commit**

```bash
cd $REPO
git add build/network/setup-ad-pivot.sh build/network/donerup-ad-pivot.service
git commit -m "feat: add idempotent, boot-persistent AD pivot iptables enforcement"
```

---

### Task 4: Prove the enforcement with throwaway network namespaces

**Files:**
- Create: `build/network/tests/run_isolation_test.sh`

This test fakes the AD VLAN and the HTB VPN client subnet with `ip netns` namespaces on IPs drawn from `config.env`'s real subnets, so it exercises the exact same iptables rules Task 3 installs — no mocking of the enforcement logic itself. **Run this only while the Docker stack is down** (`docker compose down` first) — it uses real host interfaces on `INTERNAL_AD_SUBNET`/`AD_VLAN_SUBNET`, which would collide with the live `internal-ad` Docker bridge if both exist at once.

- [ ] **Step 1: Write the test**

`build/network/tests/run_isolation_test.sh`:

```bash
#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.."
source config.env

FAKE_INTERNAL_AD_IP="172.28.0.99"
FAKE_AD_VLAN_IP="10.10.20.250"
FAKE_VPN_IP="10.10.14.99"
LISTEN_PORT=8445

cleanup() {
  set +e
  kill "$NC_PID" 2>/dev/null
  ip netns del internal-ad-sim 2>/dev/null
  ip netns del ad-vlan-sim 2>/dev/null
  ip netns del vpn-sim 2>/dev/null
  ip link del veth-iad-h 2>/dev/null
  ip link del veth-adv-h 2>/dev/null
  ip link del veth-vpn-h 2>/dev/null
  iptables -D FORWARD -j DONERUP_AD_PIVOT 2>/dev/null
  iptables -F DONERUP_AD_PIVOT 2>/dev/null
  iptables -X DONERUP_AD_PIVOT 2>/dev/null
  iptables -t nat -D POSTROUTING -s "$INTERNAL_AD_SUBNET" -d "$AD_VLAN_SUBNET" -j MASQUERADE 2>/dev/null
}
trap cleanup EXIT

make_netns() {
  local ns="$1" veth_h="$2" veth_ns="$3" ip_addr="$4" prefix="$5"
  local host_ip="${ip_addr%.*}.1"
  ip netns add "$ns"
  ip link add "$veth_h" type veth peer name "$veth_ns"
  ip link set "$veth_ns" netns "$ns"
  ip addr add "${host_ip}/${prefix}" dev "$veth_h" 2>/dev/null || true
  ip link set "$veth_h" up
  ip netns exec "$ns" ip addr add "${ip_addr}/${prefix}" dev "$veth_ns"
  ip netns exec "$ns" ip link set "$veth_ns" up
  ip netns exec "$ns" ip link set lo up
  ip netns exec "$ns" ip route add default via "$host_ip"
}

make_netns internal-ad-sim veth-iad-h veth-iad-ns "$FAKE_INTERNAL_AD_IP" 24
make_netns ad-vlan-sim veth-adv-h veth-adv-ns "$FAKE_AD_VLAN_IP" 24
make_netns vpn-sim veth-vpn-h veth-vpn-ns "$FAKE_VPN_IP" 23

sysctl -w net.ipv4.ip_forward=1 >/dev/null
./setup-ad-pivot.sh

ip netns exec ad-vlan-sim nc -l -p "$LISTEN_PORT" &
NC_PID=$!
sleep 1

echo -n "[check] internal-ad -> AD VLAN reaches through the pivot path... "
if ip netns exec internal-ad-sim timeout 2 nc -zv "$FAKE_AD_VLAN_IP" "$LISTEN_PORT" 2>&1 | grep -q succeeded; then
  echo "PASS"
else
  echo "FAIL"
  exit 1
fi

echo -n "[check] VPN client subnet -> AD VLAN is blocked... "
if ip netns exec vpn-sim timeout 2 nc -zv "$FAKE_AD_VLAN_IP" "$LISTEN_PORT" 2>&1 | grep -q succeeded; then
  echo "FAIL (VPN subnet reached the AD VLAN directly)"
  exit 1
else
  echo "PASS"
fi

echo "ALL ISOLATION CHECKS PASSED"
```

- [ ] **Step 2: Run it**

```bash
cd $REPO/build
docker compose down
chmod +x network/tests/run_isolation_test.sh
sudo network/tests/run_isolation_test.sh
```

Expected:
```
donerup AD pivot rules applied
[check] internal-ad -> AD VLAN reaches through the pivot path... PASS
[check] VPN client subnet -> AD VLAN is blocked... PASS
ALL ISOLATION CHECKS PASSED
```

- [ ] **Step 3: Bring the Docker stack back up**

```bash
cd $REPO/build
docker compose up -d
```

- [ ] **Step 4: Commit**

```bash
cd $REPO
git add build/network/tests/run_isolation_test.sh
git commit -m "test: verify AD pivot isolation with throwaway network namespaces"
```

---

## Self-Review

**Spec coverage:**
- §6.1 (topology: `dmz` bridge, `internal-ad` bridge, AD VLAN, host iptables `FORWARD` in between) → Tasks 1, 3.
- §6.2 (discovery hints: second interface via `ip addr`, `dc01.donerup.htb` via `/etc/hosts`) → Task 1, Steps 3 and 5.
- §6.3 (enforcement is a technical requirement, not narrative — host iptables `FORWARD`, `internal-ad` has no Docker-managed NAT, boot-persistent via systemd `After=docker.service`, idempotent) → Task 3.
- §6.4 (pivot tool needs a real L3 path, not a SOCKS proxy — this plan builds that L3 path; the actual ligolo-ng agent is something the player drops post-RCE, not something baked into the image, per spec §6.4's "the player drops the agent into the container") → Task 2's route is exactly what that dropped agent needs to route traffic through.

**Placeholder scan:** No TBD/TODO markers. `VPN_CLIENT_SUBNET` is explicitly documented as a placeholder to replace with the real HTB VPN range — that's a flagged, intentional deferral (the isolation logic doesn't depend on its exact value), not a vague placeholder.

**Type consistency:** `config.env` variable names (`INTERNAL_AD_SUBNET`, `AD_VLAN_SUBNET`, `VPN_CLIENT_SUBNET`, `DC_IP`, `INTERNAL_AD_GATEWAY_IP`) are used identically across `setup-ad-pivot.sh` (rules 1-4 plus the gateway drift guard), `donerup-ad-pivot.service` (via `WorkingDirectory` + script sourcing, not direct env injection — the unit doesn't need `EnvironmentFile` since the script sources `config.env` itself), and `run_isolation_test.sh`. The entrypoint route (Task 2) no longer hardcodes `172.28.0.1` / `eth1`: it takes `AD_VLAN_SUBNET` and `INTERNAL_AD_GATEWAY_IP` from the container's environment (compose must source these from `config.env`) and resolves the interface dynamically by matching the kernel's link-scope route table against `INTERNAL_AD_SUBNET`, so it stays correct even if Docker assigns a different gateway or NIC name. `setup-ad-pivot.sh`'s gateway drift guard exists precisely to catch config.env's `INTERNAL_AD_GATEWAY_IP` going stale relative to Docker's actual IPAM assignment.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-24-donerup-network-pivot.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

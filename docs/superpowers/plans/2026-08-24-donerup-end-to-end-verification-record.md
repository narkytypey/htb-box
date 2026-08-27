# Donerup Plan 4 — Verification Record

Companion to `2026-08-24-donerup-end-to-end.md`. Records what was actually
verified when Plan 4 was executed, and what remains open. It was originally
left uncommitted, since Plan 4 Task 4 specifies no file deliverables; it is
now tracked, because the 2026-08-27 section at the end documents defects that
future work needs to be able to read.

**Executed:** 2026-08-25 · branch `build/donerup` · commits `90672f3` through `11f912a`

---

## Environment at execution time

There was **no Windows DC**. `10.10.20.10` did not respond, the `adlab0`
AD-VLAN bridge did not exist, and none of Plan 3's PowerShell had ever run
against a live host. *(Superseded on 2026-08-27 — see
"Plan 3 provisioning against a real DC" at the end of this document.)* The Docker stack (`build-web-1`, `build-legacy-auth-db-1`)
was up. `pwsh`, `certipy` v5.0.4, `impacket`, `nmap`, `sshpass` were installed.

Everything below follows from that: all file deliverables were completed and
committed; verification split into what could genuinely run and what could not.

---

## Task 1 — Real LDAP bind

Delivered: `build/web/.env.real-ldap.example`, `.gitignore` entry, the
gitignored `build/web/.env.real-ldap`, and the `build/docker-compose.yml`
switch off mock mode.

**Deviation from the plan (controller-approved).** The plan's Step 4 YAML
hardcodes `10.10.20.10` / `172.28.0.10` and drops `AD_VLAN_SUBNET`,
`INTERNAL_AD_SUBNET`, `INTERNAL_AD_GATEWAY_IP`. Applying it literally would
regress commit `6fcc4bf` and silently break `docker-entrypoint.sh`, which reads
all three at runtime to install the AD-VLAN route — its `if/elif/else` would
drop the route while the container still reported healthy. Only two changes were
made: `LDAP_MODE: mock` deleted, `env_file` added. All `${VAR:?}` interpolations
kept.

**Step 5 — FAILED, as expected.** `integration_smoke.py` fails on its *first*
check. `real_ldap_connection()`'s `auto_bind=True` blocks in `socket.connect()`
to the unreachable DC until gunicorn's 30s worker timeout fires
(`[CRITICAL] WORKER TIMEOUT`), so the app returns HTTP 500.

Confirmed to be connectivity, not misconfiguration: `env | grep LDAP_` inside the
container shows all three vars injected from the env_file, and `ip route` shows
`10.10.20.0/24 via 172.28.0.1 dev eth1` present.

> **§11 item "LDAP injection needs re-verification against real AD, not mock"
> is STILL OPEN.** The commit message says "re-verify injection against real AD"
> because the plan pinned that wording; the re-verification did not happen.

---

## Task 2 — `root.txt` on the DC

Delivered: `build/dc-provisioning/06-place-root-flag.ps1` and
`checks/check-root-flag.ps1`.

Verified locally: both parse clean under `pwsh`; the check script's three
branches (missing / non-hex / valid) behave correctly against a substituted path
in a throwaway copy; `([guid]::NewGuid().Guid -replace '-','')` yields 32
lowercase hex chars matching `^[a-f0-9]{32}$`.

**Defect found in the plan's own script text and fixed** (`04d277b`): the plan's
`icacls ... | Out-Null` swallowed failures — `icacls` writes failures to stdout,
not PowerShell's error stream, and there was no `$LASTEXITCODE` check, so the
script printed success and exited 0 even when the ACL lockdown never applied.
`check-root-flag.ps1` only checked presence and format, so it would print PASS
with `root.txt` sitting at its inherited Desktop ACL — readable without Domain
Admin, defeating the gate the flag depends on (spec §10). `06-` now captures
output and fails loudly; the check now asserts `Administrators` is granted and no
broader principal (`Users`/`Everyone`/`Authenticated Users`/`Domain Users`) appears.

Caveats on that fix: the ACL assertion has only ever run against **synthetic**
stand-ins for `Get-Acl`/AD ACE objects (no live Windows/AD on Linux to exercise
`Get-Acl` or `Get-ADDomain` for real).

**Update (`1597ab1`):** the English-only-text exposure this section originally
flagged in `check-acl.ps1` is now fixed there too — it matched `dsacls`'s
printed rights/trustee text the same way `check-root-flag.ps1` used to match
`icacls` text; replaced with `Get-Acl "AD:..."` + SID translation against
svc_ldap's actual SID, mirroring this fix. Also closed: `check-root-flag.ps1`
silently skipped adding the Domain Users broad-principal entry whenever
`Get-ADDomain` returned nothing, so a Domain Users grant would have passed
unexamined — now emits a WARN, same principle as the untranslatable-ACE WARN
below. Both verified via synthetic exercise only, same caveat as above.

Final review then caught a follow-on: re-running `06-` to apply that very ACL
fix on an already-live DC silently minted a *new* flag, invalidating one players
may already hold. `11f912a` guards flag generation the way
`docker-entrypoint.sh` guards `user.txt`, while leaving `icacls` unconditional so
the script still works as a repair step. Verified under `pwsh` with a stubbed
`icacls`: first run writes, re-run preserves the flag.

**Blocked:** Steps 2, 4 (run on the DC) and Step 5 (remote read via
`impacket-wmiexec` with the recovered admin hash).

---

## Task 3 — Full chain replay

Delivered: `build/exploit/full-chain-replay.sh`.

**Two Critical defects in the plan's script text, fixed** (`b6ec145`) — both
would break Phase 8 against a *real, fully compromised* DC, not just this lab:

1. `-hashes ":$ADMIN_HASH"` was malformed. `ADMIN_HASH` is extracted with
   `[a-f0-9:]+`, which captures certipy's `LMHASH:NTHASH` pair, so the colon
   prefix produced three colon-delimited fields and impacket rejects it. The
   colon idiom was correct for `SVC_BACKUP_HASH` (a bare NT hash) in
   `run-esc9-chain.sh` and appears to have been copied across.
   → now `-hashes "$ADMIN_HASH"`.
2. Phase 8 hardcoded `dc01.donerup.htb`, contradicting `run-esc9-chain.sh`'s own
   documented rationale that no provisioning step establishes a DC hostname, so
   it fails at name resolution over the tunnel. → now `@$DC_IP`.

Three false-PASS risks also fixed: Phase 2 could report "rabbit hole is clean"
when the query never ran (now requires positive evidence the table came back);
Phase 8 could read a stale `/tmp/esc9-auth.out` from an earlier session (now
removed at start); Phase 0's pattern passed when *any single* in-scope port was
closed while others were open (now asserts no in-scope port is open). Plus
`cd ... || exit 1`, and `WEB_HOST` — previously dead while advertised in the
usage string — now wired through a `BASE_URL` env var that defaults to the
original value.

The Phase 0 rewrite initially introduced a regression of its own — a negated
`open` check passes when nmap produces *no* port table at all (host-timeout
expiring, insufficient privileges), turning "couldn't scan" into "isolation
confirmed". Caught in re-review and closed by requiring an
`Nmap scan report for` line before trusting the absence of `open` (`e413bb1`).

### Replay results in this environment

| Phase | Result | Notes |
|---|---|---|
| 0 · AD VLAN unreachable pre-pivot | **Vacuous PASS** | nmap did produce a real scan report (all three ports `filtered`, none `open`), so the positive-evidence guard is genuinely satisfied — but with nothing behind `10.10.20.10`, "filtered" can't be distinguished from "nothing answering". Proves nothing about the isolation control here. |
| 1 · Web foothold (LDAP inj → SSTI) | **FAIL** | LDAP bind to unreachable DC; gunicorn worker timeout → 500. |
| 2 · Rabbit hole is a dead end | **Genuine PASS** | `init.sql` holds only `test_user1`/`test_user2`/`demo`; the query really ran. |
| 3 · CHANGELOG.md hint | **Genuine PASS** | `/home/appuser/CHANGELOG.md` contains `LDAP_BIND_DN`. |
| 4 · Pivot tunnel | manual | Interactive pause, by design. |
| 5 · ESC9 confirmed | **FAIL** | certipy times out; no DC. |
| 6 · ESC9 → DCSync | **FAIL** | DNS resolution of `DONERUP.HTB` times out. |
| 7 · `user.txt` present | **Genuine PASS** | 33 bytes, 32-hex flag, in the container. |
| 8 · `root.txt` via admin hash | **FAIL** | Phase 6 never produced `/tmp/esc9-auth.out`. |

Exit code 1, 4 phases failed. **Three genuine passes, one vacuous, five
DC-dependent failures.**

---

## Task 4 — Spec §11 open items

| §11 item | Status | Evidence |
|---|---|---|
| SSH is a genuine dead end (cred reuse) | **CLOSED** (`b147c15`, code-level; not yet run live) | The plan's Task 4 Step 1 snippet now has a three-way branch — `Permission denied` → PASS, `Connection refused`/no-route/timeout/etc → SKIP, anything else → FAIL — instead of conflating "rejected by a live sshd" with "sshd reachable". Fixes the exact gap this row originally flagged. Still not executed against a live sshd; the plan explicitly documents SKIP as the expected outcome in this environment. |
| Tunnel DNS via `-ns <DC_IP>` | **CLOSED** (`3b5535f`, `1a7cb17`, `28d7b1c`, code-level; not yet run live) | The plan's Task 4 Step 2 snippet now has an explicit `else` branch (no more silent-nothing on failure), gates PASS on certipy's own `"Enumeration output:"` marker rather than exit code alone, and its prose now correctly documents that `-dc-ip` (an IP literal) short-circuits certipy's resolver — so this exact invocation does **not** exercise `-ns`/DNS, and the plan says so rather than claiming otherwise. Still not executed against a live DC. |
| Reset resilience across reboot | **STILL OPEN** | Not executed — `sudo reboot` would end the session, and `run_isolation_test.sh` requires the stack down. Read-only inspection found something the plan assumed away: **`donerup-ad-pivot.service` is not installed on this host at all** (`systemctl status` → "could not be found"; nothing in `/etc/systemd/system/`). The repo's unit file does have `After=docker.service`, `Requires=docker.service` and `WantedBy=multi-user.target`, so it *would* start unattended — but Plan 2's install step was never performed here, so a reboot today would prove nothing. |

### Operator runbook for the deferred reboot test

1. Install and enable the unit (missing precondition): copy
   `build/network/donerup-ad-pivot.service` to `/etc/systemd/system/`, install
   the script to `/opt/donerup/network/`, `systemctl enable --now` it.
2. `sudo reboot`.
3. `systemctl status donerup-ad-pivot.service --no-pager` → expect `active (exited)`.
4. `systemctl is-enabled donerup-ad-pivot.service` → expect `enabled`.
5. `docker compose down` (from `build/`).
6. `sudo build/network/tests/run_isolation_test.sh` → expect `ALL ISOLATION CHECKS PASSED`.
7. `cd build && docker compose up -d`.
8. `python3 web/tests/integration_smoke.py` → expect `ALL INTEGRATION CHECKS PASSED`
   (requires a reachable DC — see Task 1).

---

## What must happen before this box is deployable

1. **Stand up the Plan 3 DC** on the `adlab0` AD VLAN at `10.10.20.10` and run
   `01-` … `06-` with their checks. Everything else below depends on this.
2. **Re-run Task 1 Step 5** — the actual close of §11's mock-vs-real LDAP item.
   The real AD filter parser is not guaranteed to treat the verified
   full-width-parenthesis payload the way `ldap3`'s `MOCK_SYNC` did.
3. **Re-run `full-chain-replay.sh`** over a live ligolo tunnel; Phases 0, 5, 6, 8
   have never executed meaningfully.
4. **Exercise `check-root-flag.ps1` and `check-acl.ps1`'s ACL assertions against
   a real DC.** Both are `Get-Acl`/SID-based now (`icacls`/`dsacls` text
   matching removed entirely, `1597ab1`) — only ever run against synthetic
   stand-ins for `Get-Acl`/`Get-ADDomain`/`Get-ADUser` output on Linux.
5. **Install + enable `donerup-ad-pivot.service`**, then run the reboot test.
6. ~~Fix the plan's Task 2 Step 5 snippet — it carries the same malformed
   `-hashes ":$ADMIN_HASH"` and hardcoded `dc01.donerup.htb` that were corrected
   in the replay script, so anyone re-deriving from the plan text reintroduces
   both bugs.~~ **RESOLVED.** The Task 2 Step 5 snippet in
   `2026-08-24-donerup-end-to-end.md` now reads `-hashes "$ADMIN_HASH"` and
   `@$DC_IP`, matching the fix `b6ec145` applied to `full-chain-replay.sh`.

## Operator gotchas at deploy time

- **First run after cloning:** `cp build/web/.env.real-ldap.example
  build/web/.env.real-ldap` before `docker compose up`, or Compose refuses to
  start the *whole* stack (a missing `env_file` is a hard error, not a per-service
  one). The compose file carries an inline comment saying so. This loud failure is
  preferable to `required: false`, which would start the app with an empty bind
  password and surface as a confusing runtime LDAP error instead.
  **Then edit the copy:** the example ships `LDAP_BIND_PASSWORD=REPLACE_ME`, not
  the real value — committing the live svc_ldap password would put the spec §5
  bind credential in git history, where players could read it instead of finding
  it in the container. The provisioned value is the one in
  `dc-provisioning/02-create-users.ps1`'s `New-ADUser` call for `svc_ldap`.
  Note this *is* the "confusing runtime LDAP error" case the paragraph above
  argues against: the bind is lazy, so leaving `REPLACE_ME` in place starts the
  stack cleanly and only fails on the first login attempt. That trade was taken
  deliberately — a secret in git is worse than a late error — but it means a
  failed login on a fresh deploy should send you here first.
- ~~**If replay Phase 6 fails partway,** don't trust the one-line `[FAIL]`.
  `run-esc9-chain.sh` swaps `svc_backup`'s UPN to `administrator` at step 2 and
  restores it at step 4; under `set -euo pipefail` a step-3 failure exits before
  the restore, leaving a duplicate-UPN condition in the domain. Check
  `svc_backup`'s UPN manually before re-running.~~ **FIXED** (`1597ab1`): a
  `trap ... EXIT` now runs the restore on any exit path, guarded against
  double-execution. Verified with a stubbed `certipy` that fails step 3 —
  restore call confirmed logged. Not yet exercised against a real domain.
- **`check-esc9.sh` used to die silently on a certipy failure** (DC
  unreachable/timeout) — `set -e` killed it mid-pipeline before it ever
  printed a `FAIL:` line, same shape already fixed for the SSH/DNS checks
  above. **FIXED** (`1597ab1`): captures certipy's exit code via
  `PIPESTATUS` and reports it explicitly. Verified with a stubbed failing
  `certipy`.


---

## Plan 3 provisioning against a real DC — 2026-08-27

Supersedes the "no Windows DC" premise recorded above. A Windows Server 2022
Datacenter Evaluation VM (hostname `DC01`, `10.10.20.10/24` on VMnet3) was
built and every `build/dc-provisioning/` script was run against it with its
paired red/green check.

**How it was driven:** from the Windows host through `vmrun` guest operations
(`runProgramInGuest`, `CopyFileFromHostToGuest`) once VMware Tools was
installed, not by typing at the VM console. The scripts were staged in the
guest at `C:\donerup\`. This matters for anyone repeating the run: without
Tools there is no clipboard and no host-to-guest file channel, and installing
Tools is the first thing worth doing on a fresh VM.

| Task | Script | Check | Result |
|------|--------|-------|--------|
| 1 | `01-promote-dc.ps1` | `check-domain.ps1` | PASS — `donerup.htb`, Windows2016Forest |
| 2 | `02-create-users.ps1` | `check-users.ps1` | PASS after the fix below |
| 3 | `03-grant-svc-backup-acl.ps1` | `check-acl.ps1` | PASS — GenericWrite confirmed by SID |
| 4 | `04-install-adcs-esc9.ps1` | `check-esc9.sh` | PASS after the fix below — certipy flags ESC9 |
| 5 | `05-weaken-cert-binding.ps1` | `check-cert-binding.ps1` | PASS — `StrongCertificateBindingEnforcement=1` |
| 6 | `06-place-root-flag.ps1` | `check-root-flag.ps1` | PASS — `Administrators:(R)` / `SYSTEM:(F)` |

Two real defects surfaced. Both were caught by the check scripts; **neither
provisioning script reported a failure of its own**, which is the part worth
remembering.

### `02-create-users.ps1` — the `Users` OU collides with the built-in container

`New-ADOrganizationalUnit -Name "Users" -Path "DC=donerup,DC=htb"` fails with
error 8305 (*name already in use*): the domain root already carries the
built-in `CN=Users` container and the RDN collides. `OU=Users` therefore never
existed, and `New-ADUser -Path "OU=Users,..."` for `jdoe` failed with
*Directory object not found*.

The script had no `$ErrorActionPreference` setting, so it ran on through both
failures, printed `administrator.info confirmed absent`, and **exited 0 with
`jdoe` missing**. A half-provisioned domain that reports success is worse than
a loud failure; only `check-users.ps1` caught it.

Fixed in the working tree: the OU is now `Employees` (nothing outside this
script referenced `OU=Users` — the web app searches the whole subtree from
`dc=donerup,dc=htb`, so the OU name is cosmetic), `$ErrorActionPreference =
"Stop"` is set, and OU/user creation is idempotent so the script can be re-run
after a partial failure.

### `04-install-adcs-esc9.ps1` — blind attribute copy, and two settings that would have blocked enrolment

The template duplication looped over `$userTemplate.PropertyNames` and copied
every property onto the new object. That hashtable contains nulls and
operational attributes (`instanceType`, `objectCategory`, `uSNCreated`, ...),
so `New-ADObject` rejected it wholesale with *the argument is null or an
element of the argument collection contains a null value*. The template was
never created, and the five statements after it each failed against a
non-existent object — ending in `CertUtil: -SetCATemplates command FAILED`,
which points at the wrong step entirely.

Two further problems only visible once the real `User` template was dumped:

- `msPKI-Certificate-Name-Flag` is `0xA6000000`, which includes
  `CT_FLAG_SUBJECT_REQUIRE_EMAIL` and `CT_FLAG_SUBJECT_ALT_REQUIRE_EMAIL`.
  No domain account has a `mail` attribute, so enrolment would have been
  refused with *the email name is unavailable and cannot be added to the
  Subject or Subject Alternate name*. Now `0x82000000`
  (`SUBJECT_REQUIRE_DIRECTORY_PATH` | `SUBJECT_ALT_REQUIRE_UPN`) — the UPN in
  the SAN is what ESC9 pivots on.
- The clone stayed at schema version 1 and carried three EKUs (EFS, Secure
  Email, Client Authentication). It is now schema version 2 with
  `msPKI-Certificate-Application-Policy` set and Client Authentication only.

Fixed in the working tree: an explicit attribute allowlist replaces the blind
copy, a unique `msPKI-Cert-Template-OID` is generated under the forest arc,
`CT_FLAG_AUTO_ENROLLMENT` is cleared from `flags`, `Install-AdcsCertificationAuthority`
is skipped when a CA is already configured, `certutil` failures throw, and
`CertSvc` is restarted after publishing.

Confirmed from the attacker side afterwards — `certipy find -vulnerable`
reports `Enrollment Flag: NoSecurityExtension`, `Certificate Name Flag:
SubjectAltRequireUpn / SubjectRequireDirectoryPath`, `Schema Version: 2`,
`Enrollment Rights: DONERUP.HTB\Authenticated Users`, and
`ESC9: Template has no security extension.`

### Still open after this run

- **The exploitation chain has still never been run.**
  `build/exploit/run-esc9-chain.sh` and `full-chain-replay.sh` remain
  unexercised against the real domain; everything above only proves the
  misconfigurations exist, not that they chain.
- **`run-esc10-check.sh` was never written.** It appears in Plan 3's file
  structure and in its Task 7, but no such file exists.
- **`dcdiag` fails `DFSREvent` and `SystemLog`** — both are 24-hour event-log
  artefacts (DFSR starting before AD DS on the first post-promotion boot; a
  hard power-off plus a VMware Tools timeout). Live state is healthy:
  `DfsrReplicatedFolderInfo.State = 4`, `SYSVOL`/`NETLOGON` shared,
  `dcdiag /test:Services` and `/test:Replications` silent.
- **The fixes above are in the working tree, uncommitted.**

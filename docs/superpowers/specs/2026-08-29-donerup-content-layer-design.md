# Donerup — Content Layer Design (world canon, texture, fair-hint reinforcement)

Date: 2026-08-29
Status: approved, ready for implementation planning
Scope: `build/dc-provisioning/` (roster data + provisioning loop + checks),
`build/legacy-auth-db/init.sql` (decor tables), `build/web/app/templates/`,
`build/web/app/static/css/donerup.css`, `build/web/content/` (new),
`build/web/Dockerfile`, `build/web/tests/` (new consistency test).

## Problem

Donerup's exploitation chain is built and empirically verified end to end —
LDAP injection, SSRF, SSTI, pivot, ESC9, Certifried, DCSync. The *world the
chain lives in* is not. Concretely, as of `a241b0c`:

- The dashboard renders one line: `Welcome, {account_name}`.
- The Report Builder is an empty `<textarea>`; Branding is one input.
- The whole domain holds three accounts (`jdoe`, `svc_ldap`, `svc_backup`)
  plus the built-ins. A BloodHound collection against a European restaurant
  group returns a graph with essentially nothing in it.
- `legacy-auth-db` holds three rows in one `users` table.
- Every load-bearing hint in the box lives in exactly one file,
  `build/web/CHANGELOG.md`, which simultaneously carries the rabbit-hole
  "not here" signal, the `info` migration mechanic, and the location of the
  bind credential. A player who misses that one file has nothing.

There is also a live contradiction: `CHANGELOG.md` states the legacy database
is kept online "only for a handful of legacy read-only shift reports", but the
database contains no shift reports at all. A player who breaks into the rabbit
hole finds it *provably* empty, which reads as a designer's dead end rather
than a decommissioned system — weakening the "fair rabbit hole" principle in
`donerup-htb-insane-design-v2.md` §1.

## Decisions taken in brainstorming (constraints on everything below)

1. **The chain is untouchable.** No new exploitable step, no change to any
   existing mechanic, payload, gate, credential, or verification script's
   intent. Every addition is inert content.
2. **Hints reinforce only.** New content may repeat, in a different voice,
   something `CHANGELOG.md` or an already-visible response already says. It
   may never disclose new information, and it may never let a player skip a
   step.
3. **AD gets a full roster** — 22 additional accounts, an OU tree, groups,
   and directory attributes.
4. **Strict credential policy.** The three existing MD5 rows
   (`pideci06`, `kokorec99`, `misir2020`) stay and are the *only*
   credential-shaped strings in the box's filler. No new hashes, no new
   plaintext passwords, no `.bak` files, no hardcoded test credentials.
5. **Approach C (hybrid).** The one genuinely repetitive artifact — the AD
   roster — is data-driven from a CSV. Everything else is handwritten for
   voice, and held consistent by a test rather than by a generator.

## Non-goals

- No new HTTP routes, services, containers, or VMs.
- No new ACL edges, group memberships, or delegation in AD. The
  `svc_ldap → svc_backup` `GenericWrite` edge remains the only interesting
  one; texture supplies graph *noise*, never graph *paths*.
- No easter eggs, jokes, or tonal breaks. In an Insane box a tonal break is
  read as a signal.
- No change to `build/web/CHANGELOG.md`. It stays byte-identical; it is the
  most load-bearing text in the box.
- No change to the LDAP filter template, the sanitizer, the SSTI blacklist,
  the loopback gate, or flag placement/permissions.

## Three hard constraints discovered while writing this spec

These are not preferences. Violating any of them silently breaks the box.

### C1 — `is_privileged` is a substring match

`build/web/app/ldap_auth.py:44`:

```python
def is_privileged(member_of) -> bool:
    return any("Domain Admins" in dn for dn in member_of)
```

Any account whose `memberOf` contains a DN with the literal substring
`Domain Admins` reaches the admin panel. Group names such as
`Legacy Domain Admins`, `Domain Admins (retired)`, or an OU named
`Domain Admins Archive` would hand every member an app-admin session
without the LDAP injection. **No group, OU, or container introduced by this
work may contain that substring.** `checks/check-users.ps1` gains an
assertion enforcing it.

### C2 — the dashboard response must end with the welcome line

`build/web/tests/test_webapp.py:68`:

```python
assert resp.data.rstrip().endswith(b"Welcome, administrator")
```

This is the anti-reflection guarantee (the injection payload must never be
echoed). All new dashboard content therefore goes **above** the welcome
block, and the welcome block stays the last element in the DOM, rendered as
a signed-in footer strip. The test is not modified, and its guarantee is
preserved exactly as written.

### C3 — existing distinguished names are pinned

`CN=svc_ldap,OU=Service Accounts,DC=donerup,DC=htb` is pinned in
`build/web/.env.real-ldap`; `CN=svc_backup,OU=Service Accounts,...` is pinned
in `03-grant-svc-backup-acl.ps1`. The two existing OUs and all three existing
accounts stay exactly where they are. New OUs are added alongside; `jdoe`
is **not** moved into a sub-OU.

## The canon

Everything in the box hangs off the facts below. Where a fact was already
implied by shipped text, the source is named — nothing here overrides
existing content.

### Company

Donerup Restaurant Group: a Turkish-cuisine chain **operating in Europe**
(DACH, UK & Ireland, Benelux). This single decision reconciles the box's
existing split personality — corporate English UI copy alongside Turkish
food-derived passwords (`pideci06`, `kokorec99`, `misir2020`,
`SogukDonerAyran7`, `KebapciBind2026!Sec`, `DonerciKral99!`). Store codes are
`DNR-###`; store names are real European districts.

Forty stores: 18 DACH, 13 UK&I, 9 Benelux.

### Timeline

| Period | Event | Derived from |
|---|---|---|
| 2019–2025 | Each shop runs its own MySQL till system | `CHANGELOG.md` "one `users` table per location" |
| 2025 Q4 | Franchise consolidation programme begins | `CHANGELOG.md` "Before the franchise consolidation" |
| 2026 Q1 | Corporate LDAP directory goes live; migration copies `password_md5` into `info` | `CHANGELOG.md` "The one-time migration script" |
| 2026 Q2 | Enterprise SSO portal goes live | `login.html` "credentials now resolve against the corporate LDAP directory" |
| 2026 Q2 | Legacy till DB marked deprecated | `CHANGELOG.md` "DEPRECATED" |
| 2026 Q4 | Planned decommission — **has not happened** | `CHANGELOG.md` "slated for decommission next quarter" |

The box's present is August 2026, so "next quarter" stays true and no date
in the box goes stale.

### Partial migration (the load-bearing canon decision)

`CHANGELOG.md` already says: *"until the real password-reset rollout reaches
this region."* This spec makes that literal: **the migration completed only
for the pilot store (DNR-001 Berlin Mitte); the rollout is paused
everywhere else.**

Three consequences, all of them wanted:

- No new account needs an `info` value. Filler accounts carry **no `info`
  at all**, which satisfies the strict credential policy with zero
  exceptions and adds no new plaintext to the directory.
- `administrator` having no `info` now rests on two independent reasons —
  privileged accounts were excluded from the bulk migration
  (`donerup-htb-insane-design-v2.md` §4.1) *and* the rollout never reached
  its region. The existing rationale is reinforced, not replaced.
- Post-pivot LDAP enumeration shows `info` present on exactly one account
  and absent everywhere else. That observation confirms what `CHANGELOG.md`
  already states, in the directory's own voice, disclosing nothing new.

`jdoe` is canonically **the migration pilot test account** created by IT for
DNR-001 — which is precisely why it has a placeholder name, a weak
food-derived legacy value, and is the only `info` holder. This requires no
change to the account itself beyond a `description`.

### Menu-and-password coherence

The three existing MD5 rows become canonically meaningful at zero cost:
each shop's old till password was a menu item plus a year. `pideci06`,
`kokorec99`, `misir2020` need no modification to fit.

### Tone

Corporate European English, mildly bureaucratic, carrying real IT fatigue.
Turkish appears only in food and brand vocabulary. No humour, no
self-reference, no fourth wall.

### Character-set rule

All AD attribute values, CSV fields, SQL rows, and file contents are
**ASCII-only**. Diacritics in personal names are dropped (`Ozturk`, not
`Öztürk`). Rationale: the box's LDAP path deliberately depends on exact
byte handling of full-width Unicode payloads through nginx and ldap3;
introducing incidental non-ASCII into directory data adds an encoding
variable to a chain whose Unicode behaviour was expensive to verify.

## Layer 1 — Active Directory

### OU tree (additive only)

```
DC=donerup,DC=htb
├── OU=Employees                  [EXISTS — jdoe stays at this level]
│   ├── OU=Store Operations       [new]
│   ├── OU=Regional Management    [new]
│   ├── OU=IT                     [new]
│   └── OU=Finance                [new]
├── OU=Service Accounts           [EXISTS — svc_ldap, svc_backup unmoved]
└── OU=Leavers                    [new — disabled accounts]
```

Sub-OUs are safe: the application searches the whole subtree from
`dc=donerup,dc=htb` (`ldap_auth.LDAP_BASE_DN`).

### Groups

`Store Managers`, `Regional Managers`, `IT Operations`, `Finance Reporting`,
`Portal Report Authors`, `Till Support (legacy)`.

None contains the substring `Domain Admins` (C1). No filler account is
placed in `Domain Admins` or any built-in privileged group. `svc_ldap` and
`svc_backup` group membership is **unchanged**.

### Roster (22 new accounts)

Every filler account: password = a fresh GUID (the `svc_backup` pattern, so
no one can authenticate as it), **no `info` attribute**, and populated
`description`, `title`, `department`, `physicalDeliveryOfficeName`, `mail`,
`employeeID`, `manager`.

| sAM | Name | Title | OU | Office | EmpID | Manager | Groups |
|---|---|---|---|---|---|---|---|
| dyilmaz | Deniz Yilmaz | Chief Operating Officer | Regional Management | Berlin | EMP-1001 | — | — |
| sdemir | Selin Demir | Finance Director | Finance | Berlin | EMP-1002 | dyilmaz | Finance Reporting |
| mkaya | Merve Kaya | IT Operations Lead | IT | Berlin | EMP-1004 | dyilmaz | IT Operations |
| hschulz | Hanna Schulz | Regional Manager, DACH | Regional Management | Hamburg | EMP-1006 | dyilmaz | Regional Managers |
| owalsh | Orla Walsh | Regional Manager, UK&I | Regional Management | London | EMP-1008 | dyilmaz | Regional Managers |
| pjanssen | Pieter Janssen | Regional Manager, Benelux | Regional Management | Rotterdam | EMP-1009 | dyilmaz | Regional Managers |
| tbergmann | Tobias Bergmann | Systems Administrator | IT | Berlin | EMP-1011 | mkaya | IT Operations |
| aozturk | Ayla Ozturk | Service Desk Analyst | IT | Berlin | EMP-1019 | mkaya | IT Operations |
| rdevries | Ruben de Vries | Identity Engineer | IT | Rotterdam | EMP-1023 | mkaya | IT Operations |
| lweber | Lukas Weber | Financial Analyst | Finance | Berlin | EMP-1014 | sdemir | Finance Reporting |
| nkoc | Naz Koc | Payroll Specialist | Finance | Berlin | EMP-1017 | sdemir | Finance Reporting |
| earslan | Emre Arslan | Store Manager, DNR-001 | Store Operations | Berlin | EMP-1031 | hschulz | Store Managers, Portal Report Authors |
| jbecker | Jonas Becker | Store Manager, DNR-014 | Store Operations | Hamburg | EMP-1034 | hschulz | Store Managers, Portal Report Authors |
| fcetin | Fatma Cetin | Store Manager, DNR-022 | Store Operations | London | EMP-1038 | owalsh | Store Managers, Portal Report Authors |
| mokonkwo | Michael Okonkwo | Store Manager, DNR-027 | Store Operations | London | EMP-1041 | owalsh | Store Managers, Portal Report Authors |
| sbakker | Sanne Bakker | Store Manager, DNR-031 | Store Operations | Rotterdam | EMP-1044 | pjanssen | Store Managers, Portal Report Authors |
| ktoprak | Kerem Toprak | Store Manager, DNR-035 | Store Operations | Amsterdam | EMP-1047 | pjanssen | Store Managers, Portal Report Authors |
| lfischer | Lena Fischer | Shift Supervisor | Store Operations | Hamburg | EMP-1052 | jbecker | — |
| bsahin | Burak Sahin | Shift Supervisor | Store Operations | Berlin | EMP-1055 | earslan | Till Support (legacy) |
| cmurphy | Ciara Murphy | Area Trainer, UK&I | Store Operations | London | EMP-1058 | owalsh | — |
| gvogel | Greta Vogel | Store Manager (left 2026-03) | Leavers | Hamburg | EMP-1029 | — | — (disabled) |
| ademirci | Alp Demirci | Till Support Engineer (left 2026-01) | Leavers | Berlin | EMP-1012 | — | Till Support (legacy) (disabled) |

`rdevries` is canonically the engineer who ran the migration, and
`ademirci` the engineer who owned the legacy till system before leaving —
which is, in-world, why the decommission keeps slipping. Neither fact is
disclosed as a hint; both simply make the ticket texts in Layer 3 cohere.

`jdoe` gains only a `description`: *"Migration pilot test account, DNR-001.
Retain until the password-reset rollout completes."* Its `info`, password,
OU, and DN are untouched — `checks/check-users.ps1` keeps passing unchanged.

### Attributes that cannot be set (correction)

`whenCreated` is system-assigned, `pwdLastSet` accepts only 0/-1 in
practice, and `lastLogonTimestamp` is replication-managed. Realistic
account *ages* are therefore not achievable and are not attempted. Texture
comes exclusively from the writable attributes listed above.

### Provisioning

`02-create-users.ps1` keeps its existing three account blocks and its
`administrator.info` assertion **verbatim**. A loop is appended reading
`build/dc-provisioning/data/employees.csv`, using the existing
`Test-UserExists` / `New-OuIfMissing` idempotency pattern.

Two passes are required: accounts first, then `manager` links and group
membership — a manager object must exist before it can be referenced.

### Verification

`checks/check-users.ps1` keeps its four existing assertions unchanged and
gains three:

1. No account outside `jdoe` carries an `info` value.
2. No roster account is a member of `Domain Admins` or any built-in
   privileged group.
3. No group or OU name contains the substring `Domain Admins` (C1).

## Layer 2 — Web surfaces

### `login.html`

The migration comment and the LDAP footer line stay **byte-identical** —
they are the box's earliest hint. Pure decor is added around them: portal
build tag (`Portal 2026.2.4`), a maintenance-window notice, a copyright
line. Nothing added points at any part of the chain.

### `dashboard.html`

The largest gain, since it currently renders one line. New content goes
above the welcome block (C2), turning the page into a plausible Store Ops
landing screen:

- KPI strip: covers today, waste %, shift coverage — static numbers.
- Store table: `DNR-###`, city, region, manager — the same rows as
  `stores.csv`.
- Recent reports list, establishing Report Builder as a real workflow.
- Announcements panel, restating the paused password-reset rollout in a
  corporate voice (reinforcement only).
- Footer strip, last in the DOM: `Signed in — Welcome, {{ account_name }}`.

### `report_template.html`

The `<textarea>` stays empty. An "available report fields" list is added
alongside it, using **bare field names and no braces**:
`store_code`, `period`, `covers`, `waste_pct`, `labour_hours`.

Rationale, and this is a deliberate line: field names are product texture,
whereas `{{ }}` syntax is a direct disclosure that the page renders a
template engine — new information, and outside the reinforcement-only
constraint. **No template delimiter appears on any surface in the box.**

### `branding.html`

Field guidance and accepted formats. No wording that implies a network
position ("reachable from the portal", "internal host", etc.). SSRF
discoverability continues to rest solely on the existing 403.

### The 403 page

`webapp.py:66` currently returns the bare string
`Forbidden: internal use only`. It is re-rendered through the corporate
template, and the phrase **"internal use only" is preserved verbatim in the
visible text** — that sentence is the discoverability signal the
insane-depth design relies on. No test asserts this response body
(verified against `tests/` and `exploit/`), so the change is safe.

### No new routes

Every new endpoint is new attack surface and new verification burden. None
is added.

## Layer 3 — Container artifacts

Readable by `appuser` after RCE. `build/web/CHANGELOG.md` is unchanged; the
tree below is new, shipped into the image via `Dockerfile`.

| Path | Content | Role |
|---|---|---|
| `content/README.md` | Portal deployment notes, build version, owning team, IT Service Desk reference | decor |
| `content/docs/store-ops-runbook.md` | Shift-report procedure; mentions in passing that the till DB is retired | reinforcement |
| `content/tickets/SD-4471.txt` | "Till DB still online after deprecation" — closed, decommission deferred | repeats the rabbit hole's "not here" signal |
| `content/tickets/SD-4519.txt` | "Password reset rollout paused — UK&I and Benelux" | repeats the partial migration |
| `content/tickets/SD-4602.txt` | "Report builder unreachable from my laptop" → closed *working as intended, internal use only* | repeats the 403 the player already saw |
| `content/tickets/SD-4388.txt` | Equipment fault, menu change | decor |
| `content/data/stores.csv` | 40 stores; `manager` column resolves to roster `employeeID`s | decor + consistency spine |

Every ticket restates something the player has already encountered. None
contains a credential, hash, token, hostname, or path that is not already
visible elsewhere.

## Layer 4 — Legacy database

This layer resolves the contradiction named in Problem. The `users` table
and its three MD5 rows are **unchanged**. Four decor tables are appended:

```sql
stores(code, city, region, opened_on)
menu_items(sku, name, category, unit_price_cents)
shifts(id, store_code, shift_date, shift_type, staff_count)
shift_reports(id, shift_id, covers, gross_cents, waste_pct, note)
```

Rows are consistent with `stores.csv` and the canonical menu vocabulary. No
credential column, no hash, no token.

Effect on the rabbit hole: a player who cracks in now finds exactly what
`CHANGELOG.md` promised — read-only shift reports and nothing else — and
exits in seconds **with evidence**, rather than finding an empty table that
reads as an authoring gap. The trap stays fair and becomes convincing.

Isolation is unchanged: `legacy-auth-db` remains attached only to `dmz`,
never to `internal-ad`.

## Consistency

Approach C accepts handwritten prose, so contradiction is the risk it must
pay for. No separate canon data file is introduced —
`build/dc-provisioning/data/employees.csv` and
`build/web/content/data/stores.csv` are real shipped artifacts and serve as
the spine.

`build/web/tests/test_content_consistency.py` asserts that every store
code, person name, and employee ID appearing in the templates, the ticket
texts, the runbook, and `init.sql` resolves against those two CSVs. A drifted
name or an invented store code fails the suite.

## File inventory

```
NEW  docs/superpowers/specs/2026-08-29-donerup-content-layer-design.md
NEW  build/dc-provisioning/data/employees.csv
NEW  build/web/content/README.md
NEW  build/web/content/docs/store-ops-runbook.md
NEW  build/web/content/tickets/SD-4388.txt
NEW  build/web/content/tickets/SD-4471.txt
NEW  build/web/content/tickets/SD-4519.txt
NEW  build/web/content/tickets/SD-4602.txt
NEW  build/web/content/data/stores.csv
NEW  build/web/tests/test_content_consistency.py
MOD  build/dc-provisioning/02-create-users.ps1        existing blocks verbatim; CSV loop appended
MOD  build/dc-provisioning/checks/check-users.ps1     four assertions kept; three added
MOD  build/legacy-auth-db/init.sql                    users block verbatim; four tables appended
MOD  build/web/app/templates/login.html
MOD  build/web/app/templates/dashboard.html
MOD  build/web/app/templates/report_template.html
MOD  build/web/app/templates/branding.html
MOD  build/web/app/webapp.py                          403 rendered through the template only
MOD  build/web/app/static/css/donerup.css
MOD  build/web/Dockerfile                             COPY content/
```

Untouched by contract: `CHANGELOG.md`, `ldap_auth.py`, `sanitize.py`,
`ssti_blacklist.py`, `ssti_render.py`, `branding.py`, `.env.real-ldap*`,
every `dc-provisioning` script other than `02` and `check-users.ps1`, every
script in `build/exploit/`, and `build/network/`.

## Risks and open questions

- **CSS effort is easy to underestimate.** The dashboard is currently one
  line; a KPI strip, a data table, and an announcements panel must sit
  inside the visual language already fixed by
  `2026-08-27-donerup-portal-skin-design.md`. New components extend that
  language; they do not introduce a second one.
- **`full-chain-replay.sh` has not been read for content assertions.** A
  static read found none in `tests/` or `exploit/` for the 403 body, but
  the replay script must be run against the live lab before this work is
  called done. This is the one risk not closeable by reading.
- **Provisioning time and idempotency.** 22 additional `New-ADUser` calls
  plus a second pass for `manager`/group assignment. Re-running must stay
  safe and cheap on a box reset.
- **Roster size versus LDAP search cost** is negligible at this scale but
  should be sanity-checked once against the live DC, since every login goes
  through a subtree search.
- **HTB "avoid unstable elements".** All content is static: no cron, no
  scheduler, no generated-at-runtime data. Reset resilience rests on the
  CSV plus idempotent provisioning.

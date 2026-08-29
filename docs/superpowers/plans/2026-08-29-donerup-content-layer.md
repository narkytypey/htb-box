# Donerup Content Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill the Donerup box with a coherent, inert content layer — AD roster, web copy, container documents, and legacy-database decor — without touching a single link of the verified exploitation chain.

**Architecture:** Two shipped CSV files (`employees.csv`, `stores.csv`) act as the canonical data spine. The AD roster is generated from one of them by an appended loop in the existing provisioning script; every other surface is handwritten prose held consistent with the spine by a single pytest module. Nothing new is exploitable: no new routes, no new ACL edges, no new credentials.

**Tech Stack:** Flask/Jinja2 templates, pytest, PowerShell + ActiveDirectory module, MySQL `init.sql`, Docker.

**Spec:** `docs/superpowers/specs/2026-08-29-donerup-content-layer-design.md`

## Global Constraints

Every task's requirements implicitly include this section. Each is copied verbatim from the spec.

- **C1 — no `Domain Admins` substring.** `ldap_auth.is_privileged` is `any("Domain Admins" in dn for dn in member_of)`. No group, OU, or container introduced by this work may contain that substring, in any casing variant that would still match.
- **C2 — the dashboard response must end with the welcome line.** `build/web/tests/test_webapp.py:68` asserts `resp.data.rstrip().endswith(b"Welcome, administrator")`. All new dashboard content goes *above* the welcome block. That test is not modified.
- **C3 — pinned distinguished names.** `CN=svc_ldap,OU=Service Accounts,DC=donerup,DC=htb` and `CN=svc_backup,OU=Service Accounts,DC=donerup,DC=htb` do not move. `jdoe` stays directly under `OU=Employees`.
- **ASCII only.** Every AD attribute value, CSV field, SQL row, and content file is ASCII. `Ozturk`, never `Öztürk`.
- **No new credential-shaped strings.** The only credentials in filler content remain the three existing MD5 rows (`pideci06`, `kokorec99`, `misir2020`). No new hashes, plaintext passwords, tokens, or `.bak` files.
- **No template delimiters in player-visible copy.** `{{`, `}}`, `{%`, `%}` must never appear in *rendered* page text. (Jinja source files obviously contain them; the constraint is about what a player reads.)
- **`build/web/CHANGELOG.md` is byte-identical.** Do not touch it.
- **`login.html`'s existing hint text is byte-identical.** The HTML migration comment and the two `fineprint` lines stay exactly as they are.
- **Login page giveaway ban.** `test_webapp.py::test_login_page_seeds_the_ldap_theme` asserts the lowercased login body contains none of `inject`, `fullwidth`, `full-width`, `bypass`, `sanitiz`. New copy must avoid those substrings.
- **Hints reinforce only.** New text may restate something `CHANGELOG.md` or an already-visible response says. It may never disclose new information or let a player skip a step.

**How to run the Python tests** (from the repo root):

```bash
cd build/web && python -m pytest tests/ -v
```

---

### Task 1: The data spine — `employees.csv`, `stores.csv`, and their validation test

**Files:**
- Create: `build/dc-provisioning/data/employees.csv`
- Create: `build/web/content/data/stores.csv`
- Test: `build/web/tests/test_content_consistency.py`

**Interfaces:**
- Consumes: nothing.
- Produces: `load_employees() -> list[dict]` and `load_stores() -> list[dict]` in `test_content_consistency.py`, plus module constants `REPO`, `EMPLOYEES_CSV`, `STORES_CSV`. Tasks 2, 3, 5 and 6 import these helpers from the same module.

- [ ] **Step 1: Write the failing test**

Create `build/web/tests/test_content_consistency.py`:

```python
"""The content layer's consistency spine (spec: docs/superpowers/specs/
2026-08-29-donerup-content-layer-design.md, "Consistency").

Approach C accepts handwritten prose everywhere except the AD roster, so
contradiction is the risk it has to pay for. These tests are that payment:
every store code, person name and employee id used anywhere in the box must
resolve against the two shipped CSVs.
"""
import csv
import re
from pathlib import Path

# tests -> web -> build -> repo root
REPO = Path(__file__).resolve().parents[3]
EMPLOYEES_CSV = REPO / "build" / "dc-provisioning" / "data" / "employees.csv"
STORES_CSV = REPO / "build" / "web" / "content" / "data" / "stores.csv"

STORE_CODE_RE = re.compile(r"DNR-\d{3}")
EMP_ID_RE = re.compile(r"EMP-\d{4}")


def load_employees():
    with EMPLOYEES_CSV.open(newline="", encoding="ascii") as fh:
        return list(csv.DictReader(fh))


def load_stores():
    with STORES_CSV.open(newline="", encoding="ascii") as fh:
        return list(csv.DictReader(fh))


def test_employee_roster_has_the_specified_size():
    assert len(load_employees()) == 22


def test_employee_identifiers_are_unique():
    rows = load_employees()
    sams = [r["sam"] for r in rows]
    emp_ids = [r["employee_id"] for r in rows]
    assert len(set(sams)) == len(sams)
    assert len(set(emp_ids)) == len(emp_ids)


def test_every_manager_reference_resolves():
    rows = load_employees()
    sams = {r["sam"] for r in rows}
    for row in rows:
        if row["manager_sam"]:
            assert row["manager_sam"] in sams, row["sam"]


def test_no_roster_account_carries_an_info_value():
    """Spec: the migration completed only for the pilot store, so `jdoe` is
    the sole `info` holder in the whole directory. An `info` column here
    would put new plaintext credentials into LDAP."""
    for row in load_employees():
        assert "info" not in row


def test_no_group_name_contains_the_domain_admins_substring():
    """Constraint C1: is_privileged is a substring match, so a group named
    e.g. 'Legacy Domain Admins' would hand app-admin to every member without
    the LDAP injection."""
    for row in load_employees():
        for group in filter(None, row["groups"].split("|")):
            assert "domain admins" not in group.lower()


def test_no_roster_account_uses_a_reserved_name():
    reserved = {"administrator", "jdoe", "svc_ldap", "svc_backup", "krbtgt"}
    for row in load_employees():
        assert row["sam"].lower() not in reserved


def test_store_list_has_forty_stores_split_by_region():
    rows = load_stores()
    assert len(rows) == 40
    assert len({r["code"] for r in rows}) == 40
    counts = {}
    for row in rows:
        counts[row["region"]] = counts.get(row["region"], 0) + 1
    assert counts == {"DACH": 18, "UK&I": 13, "Benelux": 9}


def test_every_store_manager_reference_resolves():
    emp_ids = {r["employee_id"] for r in load_employees()}
    for row in load_stores():
        if row["manager_employee_id"]:
            assert row["manager_employee_id"] in emp_ids, row["code"]


def test_spine_files_are_ascii_only():
    for path in (EMPLOYEES_CSV, STORES_CSV):
        path.read_text(encoding="ascii")  # raises UnicodeDecodeError otherwise
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd build/web && python -m pytest tests/test_content_consistency.py -v`
Expected: FAIL — `FileNotFoundError` for `employees.csv`.

- [ ] **Step 3: Create `build/dc-provisioning/data/employees.csv`**

```csv
sam,display_name,title,ou,office,mail,employee_id,manager_sam,groups,enabled,description
dyilmaz,Deniz Yilmaz,Chief Operating Officer,Regional Management,Berlin,deniz.yilmaz@donerup.htb,EMP-1001,,,TRUE,Operations leadership. Sponsor of the franchise consolidation programme.
sdemir,Selin Demir,Finance Director,Finance,Berlin,selin.demir@donerup.htb,EMP-1002,dyilmaz,Finance Reporting,TRUE,Owns period-end reporting across all three regions.
mkaya,Merve Kaya,IT Operations Lead,IT,Berlin,merve.kaya@donerup.htb,EMP-1004,dyilmaz,IT Operations,TRUE,Runs the corporate directory and the store portal.
hschulz,Hanna Schulz,Regional Manager DACH,Regional Management,Hamburg,hanna.schulz@donerup.htb,EMP-1006,dyilmaz,Regional Managers,TRUE,Eighteen stores across Germany Austria and Switzerland.
owalsh,Orla Walsh,Regional Manager UK and Ireland,Regional Management,London,orla.walsh@donerup.htb,EMP-1008,dyilmaz,Regional Managers,TRUE,Thirteen stores across the UK and Ireland.
pjanssen,Pieter Janssen,Regional Manager Benelux,Regional Management,Rotterdam,pieter.janssen@donerup.htb,EMP-1009,dyilmaz,Regional Managers,TRUE,Nine stores across the Netherlands and Belgium.
tbergmann,Tobias Bergmann,Systems Administrator,IT,Berlin,tobias.bergmann@donerup.htb,EMP-1011,mkaya,IT Operations,TRUE,Portal and directory infrastructure. On call rotation A.
aozturk,Ayla Ozturk,Service Desk Analyst,IT,Berlin,ayla.ozturk@donerup.htb,EMP-1019,mkaya,IT Operations,TRUE,First line support for store portal access requests.
rdevries,Ruben de Vries,Identity Engineer,IT,Rotterdam,ruben.devries@donerup.htb,EMP-1023,mkaya,IT Operations,TRUE,Ran the one time directory migration. Owns the password reset rollout.
lweber,Lukas Weber,Financial Analyst,Finance,Berlin,lukas.weber@donerup.htb,EMP-1014,sdemir,Finance Reporting,TRUE,Weekly margin and waste analysis.
nkoc,Naz Koc,Payroll Specialist,Finance,Berlin,naz.koc@donerup.htb,EMP-1017,sdemir,Finance Reporting,TRUE,Shift hours reconciliation for DACH payroll.
earslan,Emre Arslan,Store Manager DNR-001,Store Operations,Berlin,emre.arslan@donerup.htb,EMP-1031,hschulz,Store Managers|Portal Report Authors,TRUE,Manager of the pilot store for the directory migration.
jbecker,Jonas Becker,Store Manager DNR-014,Store Operations,Hamburg,jonas.becker@donerup.htb,EMP-1034,hschulz,Store Managers|Portal Report Authors,TRUE,Covering DNR-004 while that post is vacant.
fcetin,Fatma Cetin,Store Manager DNR-022,Store Operations,London,fatma.cetin@donerup.htb,EMP-1038,owalsh,Store Managers|Portal Report Authors,TRUE,Highest covers per shift in the UK and Ireland region.
mokonkwo,Michael Okonkwo,Store Manager DNR-027,Store Operations,London,michael.okonkwo@donerup.htb,EMP-1041,owalsh,Store Managers|Portal Report Authors,TRUE,Opened the Peckham site in 2024.
sbakker,Sanne Bakker,Store Manager DNR-031,Store Operations,Rotterdam,sanne.bakker@donerup.htb,EMP-1044,pjanssen,Store Managers|Portal Report Authors,TRUE,Benelux pilot site for the new till hardware.
ktoprak,Kerem Toprak,Store Manager DNR-035,Store Operations,Amsterdam,kerem.toprak@donerup.htb,EMP-1047,pjanssen,Store Managers|Portal Report Authors,TRUE,Manages the Amsterdam Zuid site.
lfischer,Lena Fischer,Shift Supervisor,Store Operations,Hamburg,lena.fischer@donerup.htb,EMP-1052,jbecker,,TRUE,Evening shift supervisor DNR-014.
bsahin,Burak Sahin,Shift Supervisor,Store Operations,Berlin,burak.sahin@donerup.htb,EMP-1055,earslan,Till Support (legacy),TRUE,Last remaining trained operator for the retired till system.
cmurphy,Ciara Murphy,Area Trainer UK and Ireland,Store Operations,London,ciara.murphy@donerup.htb,EMP-1058,owalsh,,TRUE,New starter onboarding across the UK and Ireland region.
gvogel,Greta Vogel,Store Manager (left 2026-03),Leavers,Hamburg,,EMP-1029,,,FALSE,Left the business 2026-03. DNR-004 manager post still vacant.
ademirci,Alp Demirci,Till Support Engineer (left 2026-01),Leavers,Berlin,,EMP-1012,,Till Support (legacy),FALSE,Left the business 2026-01. Owned the legacy till system decommission.
```

- [ ] **Step 4: Create `build/web/content/data/stores.csv`**

Store codes are deliberately not contiguous by region — the chain opened sites across all three regions over fourteen years, so codes interleave. `DNR-004` has an empty manager because `gvogel` left in March and the post is still vacant.

```csv
code,city,district,region,opened_on,manager_employee_id
DNR-001,Berlin,Mitte,DACH,2011-04-18,EMP-1031
DNR-002,Berlin,Kreuzberg,DACH,2012-09-03,
DNR-003,Munich,Schwabing,DACH,2013-02-25,
DNR-004,Hamburg,St Pauli,DACH,2013-11-08,
DNR-005,Cologne,Ehrenfeld,DACH,2014-05-16,
DNR-006,London,Shoreditch,UK&I,2014-10-02,
DNR-007,Frankfurt,Bockenheim,DACH,2015-03-27,
DNR-008,Manchester,Rusholme,UK&I,2015-08-14,
DNR-009,Stuttgart,Mitte,DACH,2016-01-22,
DNR-010,Birmingham,Digbeth,UK&I,2016-06-10,
DNR-011,Vienna,Favoriten,DACH,2016-11-04,
DNR-012,Berlin,Neukolln,DACH,2017-03-17,
DNR-013,Dublin,Parnell Street,UK&I,2017-07-28,
DNR-014,Hamburg,Altona,DACH,2017-12-01,EMP-1034
DNR-015,Glasgow,Finnieston,UK&I,2018-04-13,
DNR-016,Dusseldorf,Bilk,DACH,2018-09-21,
DNR-017,Leeds,Hyde Park,UK&I,2019-02-08,
DNR-018,Zurich,Aussersihl,DACH,2019-06-28,
DNR-019,London,Camden,UK&I,2019-11-15,
DNR-020,Munich,Sendling,DACH,2020-02-21,
DNR-021,Bristol,Stokes Croft,UK&I,2020-08-07,
DNR-022,London,Dalston,UK&I,2021-01-29,EMP-1038
DNR-023,Amsterdam,West,Benelux,2021-05-14,
DNR-024,Leipzig,Sud,DACH,2021-10-01,
DNR-025,Liverpool,Kensington,UK&I,2022-02-18,
DNR-026,Nuremberg,Gostenhof,DACH,2022-07-08,
DNR-027,London,Peckham,UK&I,2024-03-15,EMP-1041
DNR-028,Brussels,Saint-Josse,Benelux,2022-11-25,
DNR-029,Edinburgh,Leith,UK&I,2023-03-10,
DNR-030,Berlin,Wedding,DACH,2023-07-21,
DNR-031,Rotterdam,Centrum,Benelux,2023-12-08,EMP-1044
DNR-032,The Hague,Schilderswijk,Benelux,2024-04-19,
DNR-033,Vienna,Ottakring,DACH,2024-08-30,
DNR-034,Antwerp,Borgerhout,Benelux,2024-11-22,
DNR-035,Amsterdam,Zuid,Benelux,2025-02-14,EMP-1047
DNR-036,Utrecht,Lombok,Benelux,2025-05-23,
DNR-037,Cardiff,Cathays,UK&I,2025-08-01,
DNR-038,Bremen,Neustadt,DACH,2025-10-17,
DNR-039,Ghent,Rabot,Benelux,2026-01-30,
DNR-040,Eindhoven,Woensel,Benelux,2026-04-24,
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd build/web && python -m pytest tests/test_content_consistency.py -v`
Expected: PASS, 9 tests.

- [ ] **Step 6: Commit**

```bash
git add build/dc-provisioning/data/employees.csv build/web/content/data/stores.csv build/web/tests/test_content_consistency.py
git commit -m "feat: add the content layer's canonical data spine"
```

---

### Task 2: Legacy database decor tables

Resolves the contradiction named in the spec's Problem section: `CHANGELOG.md` claims the database is kept online for "legacy read-only shift reports", but no such reports exist.

**Files:**
- Modify: `build/legacy-auth-db/init.sql` (append only — the `users` block stays verbatim)
- Test: `build/web/tests/test_content_consistency.py` (append)

**Interfaces:**
- Consumes: `load_stores`, `STORE_CODE_RE`, `REPO` from Task 1.
- Produces: nothing later tasks depend on.

Note, already verified: `full-chain-replay.sh:92` runs only `SELECT username FROM legacy_auth.users`, so appending tables cannot affect the rabbit-hole phase assertion.

- [ ] **Step 1: Write the failing test**

Append to `build/web/tests/test_content_consistency.py`:

```python
INIT_SQL = REPO / "build" / "legacy-auth-db" / "init.sql"


def test_init_sql_only_references_known_store_codes():
    sql = INIT_SQL.read_text(encoding="ascii")
    known = {r["code"] for r in load_stores()}
    for code in set(STORE_CODE_RE.findall(sql)):
        assert code in known


def test_init_sql_ships_the_shift_reports_changelog_promises():
    """CHANGELOG.md says the database is kept online 'only for a handful of
    legacy read-only shift reports'. Before this content layer that claim was
    false, which made the rabbit hole read as an authoring gap rather than a
    decommissioned system."""
    sql = INIT_SQL.read_text(encoding="ascii").lower()
    for table in ("stores", "menu_items", "shifts", "shift_reports"):
        assert f"create table if not exists {table}" in sql


def test_init_sql_adds_no_new_credential_columns():
    """Strict credential policy: the three existing MD5 rows are the only
    credential-shaped strings allowed in filler content."""
    sql = INIT_SQL.read_text(encoding="ascii")
    after_users = sql.split("CREATE TABLE IF NOT EXISTS stores", 1)[1]
    for banned in ("password", "passwd", "secret", "token", "hash", "MD5("):
        assert banned.lower() not in after_users.lower()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd build/web && python -m pytest tests/test_content_consistency.py -k init_sql -v`
Expected: FAIL — `test_init_sql_ships_the_shift_reports_changelog_promises` fails on the missing tables, and `test_init_sql_adds_no_new_credential_columns` fails with `IndexError` because the split marker is absent.

- [ ] **Step 3: Append the decor tables to `build/legacy-auth-db/init.sql`**

Leave every existing line untouched and append:

```sql

-- Everything below is the read-only reporting remnant referenced in
-- CHANGELOG.md: shift and takings history the finance team still pulls
-- from occasionally. No authentication data -- that moved to the corporate
-- directory during the migration.
CREATE TABLE IF NOT EXISTS stores (
    code CHAR(7) PRIMARY KEY,
    city VARCHAR(40) NOT NULL,
    district VARCHAR(40) NOT NULL,
    region VARCHAR(10) NOT NULL,
    opened_on DATE NOT NULL
);

INSERT INTO stores (code, city, district, region, opened_on) VALUES
    ('DNR-001', 'Berlin', 'Mitte', 'DACH', '2011-04-18'),
    ('DNR-004', 'Hamburg', 'St Pauli', 'DACH', '2013-11-08'),
    ('DNR-014', 'Hamburg', 'Altona', 'DACH', '2017-12-01'),
    ('DNR-022', 'London', 'Dalston', 'UK&I', '2021-01-29'),
    ('DNR-027', 'London', 'Peckham', 'UK&I', '2024-03-15'),
    ('DNR-031', 'Rotterdam', 'Centrum', 'Benelux', '2023-12-08'),
    ('DNR-035', 'Amsterdam', 'Zuid', 'Benelux', '2025-02-14');

CREATE TABLE IF NOT EXISTS menu_items (
    sku VARCHAR(12) PRIMARY KEY,
    name VARCHAR(40) NOT NULL,
    category VARCHAR(20) NOT NULL,
    unit_price_cents INT NOT NULL
);

INSERT INTO menu_items (sku, name, category, unit_price_cents) VALUES
    ('DNR-WRAP-01', 'Doner Wrap', 'main', 850),
    ('DNR-PLAT-01', 'Doner Plate', 'main', 1250),
    ('DNR-PIDE-01', 'Pide', 'main', 990),
    ('DNR-LAHM-01', 'Lahmacun', 'main', 720),
    ('DNR-KOKO-01', 'Kokorec', 'main', 1150),
    ('DNR-SIDE-01', 'Fries', 'side', 390),
    ('DNR-SIDE-02', 'Mercimek Soup', 'side', 450),
    ('DNR-DRNK-01', 'Ayran', 'drink', 260),
    ('DNR-DRNK-02', 'Salgam', 'drink', 280),
    ('DNR-DSRT-01', 'Kunefe', 'dessert', 640);

CREATE TABLE IF NOT EXISTS shifts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    store_code CHAR(7) NOT NULL,
    shift_date DATE NOT NULL,
    shift_type VARCHAR(10) NOT NULL,
    staff_count TINYINT NOT NULL
);

INSERT INTO shifts (store_code, shift_date, shift_type, staff_count) VALUES
    ('DNR-001', '2026-05-11', 'day', 5),
    ('DNR-001', '2026-05-11', 'evening', 7),
    ('DNR-014', '2026-05-11', 'day', 4),
    ('DNR-014', '2026-05-11', 'evening', 6),
    ('DNR-022', '2026-05-12', 'day', 4),
    ('DNR-022', '2026-05-12', 'evening', 8),
    ('DNR-027', '2026-05-12', 'evening', 6),
    ('DNR-031', '2026-05-13', 'day', 3),
    ('DNR-035', '2026-05-13', 'evening', 5);

CREATE TABLE IF NOT EXISTS shift_reports (
    id INT AUTO_INCREMENT PRIMARY KEY,
    shift_id INT NOT NULL,
    covers SMALLINT NOT NULL,
    gross_cents INT NOT NULL,
    waste_pct DECIMAL(4,2) NOT NULL,
    note VARCHAR(120)
);

INSERT INTO shift_reports (shift_id, covers, gross_cents, waste_pct, note) VALUES
    (1, 118, 104300, 2.10, 'Quiet lunch, delivery platform outage 12:40-13:20'),
    (2, 241, 238900, 3.40, NULL),
    (3, 96, 81200, 1.80, NULL),
    (4, 187, 176400, 4.10, 'Grill 2 down from 19:00, single line service'),
    (5, 103, 99500, 2.60, NULL),
    (6, 262, 271800, 3.90, 'Match night, extended close'),
    (7, 174, 168300, 2.20, NULL),
    (8, 71, 64100, 1.40, 'Reduced hours, staff training afternoon'),
    (9, 149, 143600, 3.10, NULL);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd build/web && python -m pytest tests/test_content_consistency.py -v`
Expected: PASS, 12 tests.

- [ ] **Step 5: Verify the rabbit-hole replay assertion is unaffected**

Run: `cd build && docker compose up -d --build legacy-auth-db && docker compose exec -T legacy-auth-db mysql -uroot -p'DonerciKral99!' -e "SELECT username FROM legacy_auth.users;"`
Expected: exactly the header `username` plus `test_user1`, `test_user2`, `demo` — no other rows, and none of `svc_ldap`, `administrator`, `jdoe`.

- [ ] **Step 6: Commit**

```bash
git add build/legacy-auth-db/init.sql build/web/tests/test_content_consistency.py
git commit -m "feat: ship the shift-report data CHANGELOG.md already promised"
```

---

### Task 3: Container document tree

**Files:**
- Create: `build/web/content/README.md`
- Create: `build/web/content/docs/store-ops-runbook.md`
- Create: `build/web/content/tickets/SD-4388.txt`
- Create: `build/web/content/tickets/SD-4471.txt`
- Create: `build/web/content/tickets/SD-4519.txt`
- Create: `build/web/content/tickets/SD-4602.txt`
- Modify: `build/web/Dockerfile` (one `COPY`, placed before the existing `chown` line)
- Test: `build/web/tests/test_content_consistency.py` (append)

**Interfaces:**
- Consumes: `load_employees`, `load_stores`, `REPO`, `STORE_CODE_RE`, `EMP_ID_RE` from Task 1.
- Produces: `CONTENT_DIR` and `content_text_files() -> list[Path]`, used by nothing later but kept for symmetry.

- [ ] **Step 1: Write the failing test**

Append to `build/web/tests/test_content_consistency.py`:

```python
CONTENT_DIR = REPO / "build" / "web" / "content"

CREDENTIAL_PATTERNS = (
    re.compile(r"\b[a-f0-9]{32}\b"),                 # md5-shaped
    re.compile(r"(?i)pass(word|wd)\s*[:=]"),
    re.compile(r"(?i)\bsecret\s*[:=]"),
    re.compile(r"(?i)\btoken\s*[:=]"),
)


def content_text_files():
    return sorted(
        p for p in CONTENT_DIR.rglob("*")
        if p.is_file() and p.suffix in {".md", ".txt"}
    )


def test_the_expected_content_documents_exist():
    names = {p.name for p in content_text_files()}
    assert names == {
        "README.md",
        "store-ops-runbook.md",
        "SD-4388.txt",
        "SD-4471.txt",
        "SD-4519.txt",
        "SD-4602.txt",
    }


def test_content_documents_reference_only_known_store_codes():
    known = {r["code"] for r in load_stores()}
    for path in content_text_files():
        for code in set(STORE_CODE_RE.findall(path.read_text(encoding="ascii"))):
            assert code in known, path.name


def test_content_documents_reference_only_known_employee_ids():
    known = {r["employee_id"] for r in load_employees()}
    for path in content_text_files():
        for emp in set(EMP_ID_RE.findall(path.read_text(encoding="ascii"))):
            assert emp in known, path.name


def test_content_documents_reference_only_known_people():
    """A name drifting between a ticket and the directory is the exact
    failure Approach C trades a generator away for."""
    known = {r["display_name"] for r in load_employees()}
    known_first = {n.split()[0] for n in known}
    for path in content_text_files():
        text = path.read_text(encoding="ascii")
        for name in re.findall(r"\b[A-Z][a-z]+ [A-Z][a-z]+\b", text):
            if name.split()[0] in known_first:
                assert name in known, f"{path.name}: {name}"


def test_content_documents_carry_no_credentials():
    for path in content_text_files():
        text = path.read_text(encoding="ascii")
        for pattern in CREDENTIAL_PATTERNS:
            assert not pattern.search(text), f"{path.name}: {pattern.pattern}"


def test_content_documents_are_ascii_only():
    for path in content_text_files():
        path.read_text(encoding="ascii")


def test_dockerfile_ships_the_content_tree_before_chown():
    """The existing `chown -R appuser:appuser ... /home/appuser` must run
    after the COPY, or the files land root-owned and appuser cannot read
    them from the RCE foothold."""
    dockerfile = (REPO / "build" / "web" / "Dockerfile").read_text(encoding="ascii")
    copy_at = dockerfile.index("COPY content/")
    chown_at = dockerfile.index("chown -R appuser:appuser")
    assert copy_at < chown_at
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd build/web && python -m pytest tests/test_content_consistency.py -k "content or dockerfile" -v`
Expected: FAIL — `test_the_expected_content_documents_exist` reports an empty set (only `data/stores.csv` exists, which has no `.md`/`.txt` suffix).

- [ ] **Step 3: Create `build/web/content/README.md`**

```markdown
# Donerup Store Portal

Portal build 2026.2.4. Owned by IT Operations (Merve Kaya, EMP-1004).

The portal is the single sign-on front end for store reporting. It runs as
a container behind the corporate TLS proxy and resolves all staff
credentials against the corporate directory. Nothing is stored locally.

## Contents of this directory

- `docs/store-ops-runbook.md` - how store managers file shift reports
- `tickets/` - exported service desk tickets kept with the deployment for
  context on outstanding issues
- `data/stores.csv` - the store list the portal renders on the dashboard

## Support

Access requests and password problems go to the IT Service Desk. Do not
raise them against this repository - directory accounts are not managed
here.
```

- [ ] **Step 4: Create `build/web/content/docs/store-ops-runbook.md`**

```markdown
# Store Operations Runbook - Shift Reporting

Audience: store managers and shift supervisors.

## Filing a shift report

1. Sign in to the store portal with your directory account.
2. Open Reports and pick the template for your region.
3. Fill in covers, waste percentage and labour hours for the shift.
4. Submit before 10:00 the following day so the regional roll-up picks it
   up.

Report templates themselves are maintained centrally by IT Operations.
Managers cannot edit them from a store machine, and requests to change a
template go through the service desk (see SD-4602 for the standing answer
on this).

## Where the numbers come from

Covers and takings come from the till export. Waste is entered by hand at
close.

## The old till reporting system

Before the corporate rollout each store filed these numbers into its own
till database. That system is retired: it is kept running read only so
finance can still pull historic shift reports, and it holds nothing current.
If you are still filing there, stop - the numbers will not reach the
regional roll-up. Decommission is owned by IT Operations and has slipped
twice already.

## Escalation

Grill and fryer faults go to facilities, not the service desk. Portal
faults go to the service desk.
```

- [ ] **Step 5: Create the four ticket files**

`build/web/content/tickets/SD-4388.txt`:

```text
Ticket:   SD-4388
Opened:   2026-06-02
Status:   Closed
Raised by: Jonas Becker (EMP-1034), DNR-014 Hamburg Altona
Assigned:  Facilities

Summary
  Grill 2 tripping the circuit during evening service.

Detail
  Second grill cuts out roughly forty minutes into evening service. Single
  line service since Thursday, covers down about fifteen percent. Reported
  to facilities by phone as well.

Resolution
  Contractor replaced the contactor 2026-06-05. Confirmed stable over two
  evening services. Closing.

  Unrelated: the summer menu change (Kunefe added, Salgam retired in DACH)
  lands 2026-07-01, tills need the new SKUs pushed before then.
```

`build/web/content/tickets/SD-4471.txt`:

```text
Ticket:   SD-4471
Opened:   2026-06-18
Status:   Closed - deferred
Raised by: Lukas Weber (EMP-1014), Finance
Assigned:  IT Operations

Summary
  Old till database still reachable months after it was declared retired.

Detail
  Finance flagged that the legacy till reporting database is still up.
  Expectation from the consolidation programme was that it would be gone
  once the directory rollout completed.

Response (IT Operations)
  Working as intended for now. It is kept running read only because a
  handful of historic shift reports have not been migrated into the portal
  yet, and finance still pulls them at period end. There is nothing current
  in it - no live staff accounts, no current takings, no directory data.
  Anything it contains predates the consolidation.

  Decommission was owned by Alp Demirci (EMP-1012), who left in January. It
  has been re-scheduled for the coming quarter. Deferring this ticket
  rather than holding it open.
```

`build/web/content/tickets/SD-4519.txt`:

```text
Ticket:   SD-4519
Opened:   2026-07-04
Status:   Open
Raised by: Orla Walsh (EMP-1008), Regional Management
Assigned:  Ruben de Vries (EMP-1023), IT Operations

Summary
  Password reset rollout has not reached UK and Ireland or Benelux.

Detail
  Managers outside DACH are asking when they get the reset prompt they were
  told to expect. Two of them have raised it with me directly this week.

Response (IT Operations)
  The rollout is paused. It completed for the pilot store, DNR-001, and
  went no further - the change window it needed collided with period end
  and was not rebooked. Nothing is broken for anyone in the meantime;
  everyone signs in normally.

  Re-planning for the coming quarter alongside the till decommission. I
  will update this ticket with a date once the window is confirmed rather
  than promise one now.
```

`build/web/content/tickets/SD-4602.txt`:

```text
Ticket:   SD-4602
Opened:   2026-08-11
Status:   Closed - working as intended
Raised by: Fatma Cetin (EMP-1038), DNR-022 London Dalston
Assigned:  Tobias Bergmann (EMP-1011), IT Operations

Summary
  Report builder page will not open from my laptop.

Detail
  Reports link on the portal dashboard returns a forbidden page saying it
  is for internal use only. Worked for me last quarter. Same result on the
  store machine and on my laptop, on and off the store network.

Response (IT Operations)
  Working as intended. The report builder is not a page staff open
  directly any more - it is internal use only and is driven by the nightly
  batch that renders the ops-requested templates. Nothing was revoked from
  your account.

  If you need a template changed, raise it against IT Operations and we
  will run it through the batch. Closing, since there is nothing to fix on
  the account side.
```

- [ ] **Step 6: Add the `COPY` to `build/web/Dockerfile`**

Insert immediately after the existing `COPY CHANGELOG.md /home/appuser/CHANGELOG.md` line, so it lands before the `RUN chmod ... && chown -R appuser:appuser` line:

```dockerfile
COPY content/ /home/appuser/portal/
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd build/web && python -m pytest tests/test_content_consistency.py -v`
Expected: PASS, 19 tests.

- [ ] **Step 8: Verify the files are readable as `appuser` in the built image**

Run: `cd build && docker compose build web && docker compose up -d web && docker compose exec -T -u appuser web ls -la /home/appuser/portal/tickets/`
Expected: four `SD-*.txt` files listed, owned by `appuser`.

- [ ] **Step 9: Commit**

```bash
git add build/web/content build/web/Dockerfile build/web/tests/test_content_consistency.py
git commit -m "feat: ship the portal document tree into the web container"
```

---

### Task 4: Login and branding page copy

**Files:**
- Modify: `build/web/app/templates/login.html`
- Modify: `build/web/app/templates/branding.html`
- Modify: `build/web/app/static/css/donerup.css`
- Test: `build/web/tests/test_webapp.py` (append)

**Interfaces:**
- Consumes: nothing.
- Produces: CSS classes `.build-tag` and `.field-help`, reused by Tasks 5 and 6.

- [ ] **Step 1: Write the failing test**

Append to `build/web/tests/test_webapp.py`:

```python
def test_login_page_carries_the_portal_build_tag():
    client = make_app().test_client()
    body = client.get("/login").data
    assert b"Portal 2026.2.4" in body


def test_login_page_keeps_its_original_hint_text_verbatim():
    """The migration comment and the LDAP footer lines are the box's
    earliest hint. Decor is added around them, never over them."""
    client = make_app().test_client()
    body = client.get("/login").data
    assert b"migration note: local auth tables retired" in body
    assert b"Authenticating against the corporate LDAP directory." in body


def test_branding_page_never_hints_at_a_network_position():
    """SSRF discoverability rests solely on the report-template 403. Copy
    here that implies a network position would hand the player the answer."""
    client = make_app().test_client()
    with client.session_transaction() as sess:
        sess["username"] = "administrator"
        sess["is_privileged"] = True
    body = client.get("/admin/branding").data.lower()
    for giveaway in (b"internal", b"loopback", b"127.0.0.1", b"localhost", b"reachable"):
        assert giveaway not in body
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd build/web && python -m pytest tests/test_webapp.py -k "build_tag or hint_text or network_position" -v`
Expected: FAIL — `test_login_page_carries_the_portal_build_tag` fails; the other two pass already and are regression guards.

- [ ] **Step 3: Add the decor to `login.html`**

Leave the HTML comment and the `fineprint` footer exactly as they are. Replace only the `<footer class="fineprint">` block's closing region by appending a build tag after it:

```html
    <footer class="fineprint">
      Authenticating against the corporate LDAP directory.<br>
      Contact IT Service Desk for access requests.
    </footer>
    <p class="build-tag">
      Portal 2026.2.4 &middot; Scheduled maintenance Sundays 02:00&ndash;04:00 CET<br>
      &copy; 2026 Donerup Restaurant Group
    </p>
```

- [ ] **Step 4: Add the field guidance to `branding.html`**

Replace the existing `<div class="field">` block with:

```html
    <div class="field">
      <label for="logo_url">Logo URL</label>
      <input id="logo_url" name="logo_url" type="text" placeholder="https://cdn.example.com/logo.png">
      <p class="field-help">
        Paste a direct link to the asset. PNG or SVG, 320&times;80 or larger,
        transparent background preferred. The file is fetched once and
        checked before it is used as report letterhead.
      </p>
    </div>
```

- [ ] **Step 5: Add the two CSS classes to `donerup.css`**

Append, matching the existing `.fineprint` idiom:

```css
.build-tag {
  margin-top: 14px;
  font-size: 12px;
  line-height: 1.6;
  color: rgba(255, 255, 255, 0.45);
  letter-spacing: 0.01em;
}

.field-help {
  margin-top: 6px;
  font-size: 13px;
  line-height: 1.5;
  color: rgba(255, 255, 255, 0.55);
}
```

- [ ] **Step 6: Run the whole web suite**

Run: `cd build/web && python -m pytest tests/ -v`
Expected: PASS — including the pre-existing `test_login_page_seeds_the_ldap_theme`, which proves the new copy introduced none of the banned giveaway substrings.

- [ ] **Step 7: Commit**

```bash
git add build/web/app/templates/login.html build/web/app/templates/branding.html build/web/app/static/css/donerup.css build/web/tests/test_webapp.py
git commit -m "feat: add login and branding page copy"
```

---

### Task 5: Dashboard content

The largest single gain: the dashboard currently renders one line. Constraint C2 governs the whole task.

**Files:**
- Modify: `build/web/app/templates/dashboard.html`
- Modify: `build/web/app/static/css/donerup.css`
- Test: `build/web/tests/test_webapp.py` (append), `build/web/tests/test_content_consistency.py` (append)

**Interfaces:**
- Consumes: `load_stores` from Task 1; `.field-help` from Task 4.
- Produces: CSS classes `.kpi-strip`, `.kpi`, `.data-table`, `.notice`.

- [ ] **Step 1: Write the failing tests**

Append to `build/web/tests/test_webapp.py`:

```python
def test_dashboard_renders_the_store_operations_content():
    client = make_app().test_client()
    with client.session_transaction() as sess:
        sess["username"] = "jdoe"
    body = client.get("/dashboard").data
    assert b"DNR-001" in body
    assert b"Covers today" in body


def test_dashboard_shows_no_template_delimiters_to_the_player():
    """No rendered surface in the box may display Jinja delimiters -- that
    would disclose the template engine rather than reinforce a known hint."""
    client = make_app().test_client()
    with client.session_transaction() as sess:
        sess["username"] = "jdoe"
    body = client.get("/dashboard").data
    for delimiter in (b"{{", b"}}", b"{%", b"%}"):
        assert delimiter not in body
```

Append to `build/web/tests/test_content_consistency.py`:

```python
TEMPLATES_DIR = REPO / "build" / "web" / "app" / "templates"


def test_templates_reference_only_known_store_codes():
    known = {r["code"] for r in load_stores()}
    for path in sorted(TEMPLATES_DIR.glob("*.html")):
        for code in set(STORE_CODE_RE.findall(path.read_text(encoding="ascii"))):
            assert code in known, path.name
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd build/web && python -m pytest tests/test_webapp.py -k dashboard tests/test_content_consistency.py -k templates -v`
Expected: FAIL — `test_dashboard_renders_the_store_operations_content` fails on the missing `DNR-001`.

- [ ] **Step 3: Rewrite the body of `dashboard.html`**

Everything new goes **above** the existing `welcome-block`. Keep the existing comment block and the welcome markup exactly as they are, and keep them last — the file must still end with `Welcome, {{ account_name }}` and no closing tag.

Insert between the `portal-bar` div and the existing comment block:

```html
<div class="content-pad">
  <div class="panel-title">Store operations &mdash; week 34</div>
  <div class="kpi-strip">
    <div class="kpi"><span class="kpi-label">Covers today</span><span class="kpi-value">1,482</span></div>
    <div class="kpi"><span class="kpi-label">Waste</span><span class="kpi-value">2.8%</span></div>
    <div class="kpi"><span class="kpi-label">Shift coverage</span><span class="kpi-value">94%</span></div>
    <div class="kpi"><span class="kpi-label">Reports outstanding</span><span class="kpi-value">3</span></div>
  </div>

  <div class="panel-title">Sites reporting</div>
  <table class="data-table">
    <thead><tr><th>Code</th><th>Site</th><th>Region</th><th>Manager</th></tr></thead>
    <tbody>
      <tr><td>DNR-001</td><td>Berlin Mitte</td><td>DACH</td><td>Emre Arslan</td></tr>
      <tr><td>DNR-004</td><td>Hamburg St Pauli</td><td>DACH</td><td>&mdash; vacant</td></tr>
      <tr><td>DNR-014</td><td>Hamburg Altona</td><td>DACH</td><td>Jonas Becker</td></tr>
      <tr><td>DNR-022</td><td>London Dalston</td><td>UK&amp;I</td><td>Fatma Cetin</td></tr>
      <tr><td>DNR-027</td><td>London Peckham</td><td>UK&amp;I</td><td>Michael Okonkwo</td></tr>
      <tr><td>DNR-031</td><td>Rotterdam Centrum</td><td>Benelux</td><td>Sanne Bakker</td></tr>
      <tr><td>DNR-035</td><td>Amsterdam Zuid</td><td>Benelux</td><td>Kerem Toprak</td></tr>
    </tbody>
  </table>

  <div class="panel-title">Recent reports</div>
  <table class="data-table">
    <thead><tr><th>Period</th><th>Site</th><th>Submitted</th></tr></thead>
    <tbody>
      <tr><td>Week 33</td><td>DNR-001</td><td>2026-08-18</td></tr>
      <tr><td>Week 33</td><td>DNR-022</td><td>2026-08-18</td></tr>
      <tr><td>Week 33</td><td>DNR-014</td><td>2026-08-19</td></tr>
      <tr><td>Week 32</td><td>DNR-031</td><td>2026-08-11</td></tr>
    </tbody>
  </table>

  <div class="notice">
    <strong>IT Operations notice.</strong> The password reset rollout is
    paused outside DACH and will be re-planned for the coming quarter. Sign
    in is unaffected. Report builder templates are maintained centrally
    &mdash; raise template changes with the service desk.
  </div>
</div>
```

- [ ] **Step 4: Add the CSS**

Append to `donerup.css`, following the existing `.panel-title` and `.portal-bar` idiom:

```css
.kpi-strip {
  display: flex;
  flex-wrap: wrap;
  gap: 14px;
  margin-bottom: 26px;
}

.kpi {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 150px;
  padding: 14px 18px;
  background: rgba(255, 255, 255, 0.04);
  border-left: 3px solid var(--orange);
}

.kpi-label {
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: rgba(255, 255, 255, 0.5);
}

.kpi-value {
  font-family: "Barlow Condensed", "Barlow", sans-serif;
  font-weight: 800;
  font-size: 30px;
  line-height: 1;
  color: var(--white);
}

.data-table {
  width: 100%;
  border-collapse: collapse;
  margin-bottom: 26px;
  font-size: 14px;
}

.data-table th {
  text-align: left;
  padding: 8px 12px;
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: rgba(255, 255, 255, 0.5);
  border-bottom: 1px solid rgba(255, 255, 255, 0.12);
}

.data-table td {
  padding: 9px 12px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
  color: rgba(255, 255, 255, 0.82);
}

.notice {
  padding: 16px 18px;
  margin-bottom: 26px;
  background: rgba(255, 255, 255, 0.04);
  border-left: 3px solid rgba(255, 255, 255, 0.25);
  font-size: 14px;
  line-height: 1.6;
  color: rgba(255, 255, 255, 0.7);
}
```

- [ ] **Step 5: Run the whole web suite**

Run: `cd build/web && python -m pytest tests/ -v`
Expected: PASS — critically including the untouched `test_dashboard_never_echoes_the_injection_payload` (C2).

- [ ] **Step 6: Commit**

```bash
git add build/web/app/templates/dashboard.html build/web/app/static/css/donerup.css build/web/tests/test_webapp.py build/web/tests/test_content_consistency.py
git commit -m "feat: build out the dashboard as a real store ops landing screen"
```

---

### Task 6: Report builder field list and the styled 403

**Files:**
- Modify: `build/web/app/templates/report_template.html`
- Create: `build/web/app/templates/forbidden.html`
- Modify: `build/web/app/webapp.py:66`
- Test: `build/web/tests/test_webapp.py` (append)

**Interfaces:**
- Consumes: `.field-help` from Task 4, `.data-table` from Task 5.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the failing test**

Append to `build/web/tests/test_webapp.py`:

```python
def test_forbidden_page_preserves_the_internal_use_only_signal():
    """That phrase is the sole discoverability signal for the SSRF step
    (spec 2026-08-28-donerup-insane-depth-design.md, Approach A). Styling
    the response must not reword it."""
    client = make_app().test_client()
    resp = client.get("/admin/report-template")
    assert resp.status_code == 403
    assert b"internal use only" in resp.data


def test_report_builder_lists_fields_without_template_delimiters():
    client = make_app().test_client()
    resp = client.get(
        "/admin/report-template", environ_overrides={"REMOTE_ADDR": "127.0.0.1"}
    )
    assert resp.status_code == 200
    assert b"store_code" in resp.data
    for delimiter in (b"{{", b"}}", b"{%", b"%}"):
        assert delimiter not in resp.data
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd build/web && python -m pytest tests/test_webapp.py -k "forbidden_page or lists_fields" -v`
Expected: FAIL — `test_report_builder_lists_fields_without_template_delimiters` fails on the missing `store_code`. `test_forbidden_page_preserves_the_internal_use_only_signal` passes already and is the regression guard for Step 4.

- [ ] **Step 3: Add the field list to `report_template.html`**

Insert after the `report-actions` div, inside `content-pad`:

```html
  <div class="panel-title">Available report fields</div>
  <table class="data-table">
    <thead><tr><th>Field</th><th>Meaning</th></tr></thead>
    <tbody>
      <tr><td>store_code</td><td>Site identifier, for example DNR-001</td></tr>
      <tr><td>period</td><td>Reporting week</td></tr>
      <tr><td>covers</td><td>Covers served in the period</td></tr>
      <tr><td>waste_pct</td><td>Waste as a percentage of gross</td></tr>
      <tr><td>labour_hours</td><td>Paid hours in the period</td></tr>
    </tbody>
  </table>
  <p class="field-help">
    Templates are maintained by IT Operations and rendered by the nightly
    batch. Raise changes with the service desk.
  </p>
```

Field names appear bare. No braces, on this or any other surface.

- [ ] **Step 4: Create `build/web/app/templates/forbidden.html`**

```html
{% extends "base.html" %}
{% block title %}Forbidden &mdash; Donerup{% endblock %}
{% block content %}
<div class="portal-bar">
  <div class="mark-row">
    {% include "_mark.html" %}
    <span class="wordmark on-dark">Donerup</span>
  </div>
  <nav class="portal-nav"><span class="current">Forbidden</span></nav>
</div>
<div class="content-pad">
  <div class="panel-title">Forbidden: internal use only</div>
  <p class="field-help">
    This page is not available from a staff workstation. If you need a
    report template changed, raise it with the IT Service Desk.
  </p>
</div>
{% endblock %}
```

- [ ] **Step 5: Render it from `webapp.py`**

Replace line 66 only. Leave the whole comment block above it untouched:

```python
        if request.remote_addr not in ("127.0.0.1", "::1"):
            return render_template("forbidden.html"), 403
```

- [ ] **Step 6: Run the whole web suite**

Run: `cd build/web && python -m pytest tests/ -v`
Expected: PASS — including every pre-existing `report-template` gate test.

- [ ] **Step 7: Commit**

```bash
git add build/web/app/templates/report_template.html build/web/app/templates/forbidden.html build/web/app/webapp.py build/web/tests/test_webapp.py
git commit -m "feat: add report builder field list and style the internal-only 403"
```

---

### Task 7: AD roster provisioning and its checks

Runs against the live DC VM. Requires the lab to be up.

**Files:**
- Modify: `build/dc-provisioning/02-create-users.ps1` (append only)
- Modify: `build/dc-provisioning/checks/check-users.ps1` (append only)

**Interfaces:**
- Consumes: `build/dc-provisioning/data/employees.csv` from Task 1.
- Produces: 22 AD accounts, four sub-OUs under `OU=Employees`, `OU=Leavers`, and six groups.

- [ ] **Step 1: Write the failing checks**

Append to `build/dc-provisioning/checks/check-users.ps1`, before the final `if ($failures -gt 0) { exit 1 }`:

```powershell
$rosterPath = Join-Path $PSScriptRoot "..\data\employees.csv"
if (-not (Test-Path $rosterPath)) {
    Write-Output "FAIL: roster CSV not found at $rosterPath"
    $failures++
} else {
    $roster = Import-Csv $rosterPath

    foreach ($row in $roster) {
        $u = Get-ADUser -LDAPFilter "(sAMAccountName=$($row.sam))" -Properties info, title, employeeID -ErrorAction SilentlyContinue
        if ($null -eq $u) {
            Write-Output "FAIL: roster account $($row.sam) does not exist"
            $failures++
            continue
        }
        if ($null -ne $u.info) {
            Write-Output "FAIL: $($row.sam).info is set - only jdoe may carry an info value"
            $failures++
        }
        if ($u.employeeID -ne $row.employee_id) {
            Write-Output "FAIL: $($row.sam).employeeID is '$($u.employeeID)', expected $($row.employee_id)"
            $failures++
        }
    }
    if ($failures -eq 0) {
        Write-Output "PASS: all $($roster.Count) roster accounts present, no info values, employeeIDs match"
    }

    # Constraint C1: ldap_auth.is_privileged is a substring match on
    # "Domain Admins", so a group or OU carrying that substring would hand
    # app-admin to its members without the LDAP injection.
    $badNames = @()
    $badNames += (Get-ADGroup -Filter * | Where-Object { $_.Name -like "*Domain Admins*" -and $_.Name -ne "Domain Admins" }).Name
    $badNames += (Get-ADOrganizationalUnit -Filter * | Where-Object { $_.Name -like "*Domain Admins*" }).Name
    if ($badNames.Count -gt 0) {
        Write-Output "FAIL: names containing the 'Domain Admins' substring: $($badNames -join ', ')"
        $failures++
    } else {
        Write-Output "PASS: no group or OU name shadows the 'Domain Admins' substring"
    }

    # No filler account may hold a privileged membership.
    $privileged = @("Domain Admins", "Enterprise Admins", "Administrators", "Account Operators", "Backup Operators")
    foreach ($groupName in $privileged) {
        $members = (Get-ADGroupMember -Identity $groupName -Recursive -ErrorAction SilentlyContinue).SamAccountName
        foreach ($row in $roster) {
            if ($members -contains $row.sam) {
                Write-Output "FAIL: roster account $($row.sam) is a member of $groupName"
                $failures++
            }
        }
    }
    Write-Output "PASS: no roster account holds a privileged group membership"
}
```

- [ ] **Step 2: Run the checks on the DC to verify they fail**

Run on the DC: `powershell -NoProfile -File .\checks\check-users.ps1`
Expected: FAIL — 22 lines of `roster account <sam> does not exist`, and a non-zero exit.

- [ ] **Step 3: Append the provisioning loop to `02-create-users.ps1`**

Append at the end of the file. Every existing block, including the `administrator.info` assertion, stays verbatim above it.

```powershell
# --- Content layer roster (spec 2026-08-29-donerup-content-layer-design.md) ---
# Inert texture only: every account below gets a GUID password (nobody can
# authenticate as it), no `info` attribute (the migration completed only for
# the pilot store, so jdoe stays the sole info holder), and no ACL edge.
# Two passes are required: an account cannot reference a manager that does
# not exist yet.

foreach ($ou in @("Store Operations", "Regional Management", "IT", "Finance")) {
    New-OuIfMissing -Name $ou -Path "OU=Employees,DC=donerup,DC=htb"
}
New-OuIfMissing -Name "Leavers" -Path "DC=donerup,DC=htb"

# No name here may contain the substring "Domain Admins" -- ldap_auth's
# is_privileged does a substring match, so such a group would bypass the
# LDAP injection entirely.
$contentGroups = @(
    "Store Managers",
    "Regional Managers",
    "IT Operations",
    "Finance Reporting",
    "Portal Report Authors",
    "Till Support (legacy)"
)
foreach ($g in $contentGroups) {
    if (Get-ADGroup -LDAPFilter "(cn=$g)" -ErrorAction SilentlyContinue) {
        Write-Output "group already present: $g"
    } else {
        New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path "OU=Employees,DC=donerup,DC=htb"
        Write-Output "created group: $g"
    }
}

$rosterPath = Join-Path $PSScriptRoot "data\employees.csv"
$roster = Import-Csv $rosterPath

# Pass 1: accounts.
foreach ($row in $roster) {
    if (Test-UserExists $row.sam) {
        Write-Output "$($row.sam) already present"
        continue
    }
    $path = if ($row.ou -eq "Leavers") {
        "OU=Leavers,DC=donerup,DC=htb"
    } else {
        "OU=$($row.ou),OU=Employees,DC=donerup,DC=htb"
    }
    $attrs = @{
        title       = $row.title
        department  = $row.ou
        company     = "Donerup Restaurant Group"
        physicalDeliveryOfficeName = $row.office
        employeeID  = $row.employee_id
        description = $row.description
    }
    if ($row.mail) { $attrs["mail"] = $row.mail }

    New-ADUser -Name $row.display_name `
        -SamAccountName $row.sam `
        -DisplayName $row.display_name `
        -Path $path `
        -AccountPassword (ConvertTo-SecureString ([guid]::NewGuid().Guid) -AsPlainText -Force) `
        -Enabled ([bool]::Parse($row.enabled)) `
        -OtherAttributes $attrs
    Write-Output "created $($row.sam)"
}

# Pass 2: manager links and group membership, now that every referenced
# object exists.
foreach ($row in $roster) {
    if ($row.manager_sam) {
        $mgr = Get-ADUser -LDAPFilter "(sAMAccountName=$($row.manager_sam))"
        Set-ADUser -Identity $row.sam -Manager $mgr
    }
    foreach ($g in ($row.groups -split '\|' | Where-Object { $_ })) {
        $members = (Get-ADGroupMember -Identity $g -ErrorAction SilentlyContinue).SamAccountName
        if ($members -notcontains $row.sam) {
            Add-ADGroupMember -Identity $g -Members $row.sam
        }
    }
}
Write-Output "roster pass 2 complete: manager links and group membership"

# jdoe's canonical role, recorded on the account itself. Its info,
# password, OU and DN are deliberately untouched.
Set-ADUser -Identity jdoe -Description "Migration pilot test account, DNR-001. Retain until the password-reset rollout completes."
Write-Output "jdoe description set"
```

- [ ] **Step 4: Copy the CSV to the DC and run provisioning**

The provisioning directory is copied to the DC as a unit; confirm `data\employees.csv` travelled with it, then run:

`powershell -NoProfile -File .\02-create-users.ps1`
Expected: four `created OU:` lines, one for `Leavers`, six `created group:` lines, 22 `created <sam>` lines, then the pass-2 and jdoe lines.

- [ ] **Step 5: Run it a second time to prove idempotency**

Run: `powershell -NoProfile -File .\02-create-users.ps1`
Expected: every line reports "already present"; no errors; exit 0. A box reset must be able to re-run this safely.

- [ ] **Step 6: Run the checks to verify they pass**

Run: `powershell -NoProfile -File .\checks\check-users.ps1`
Expected: PASS on all four original assertions plus the three new ones; exit 0.

- [ ] **Step 7: Commit**

```bash
git add build/dc-provisioning/02-create-users.ps1 build/dc-provisioning/checks/check-users.ps1
git commit -m "feat: provision the content layer AD roster from the CSV spine"
```

---

### Task 8: Live regression sweep

The content layer touches no chain mechanic by design. This task proves it against the live lab rather than asserting it.

**Files:**
- Modify: only whatever a failure in this task turns out to require.

**Interfaces:**
- Consumes: everything from Tasks 1-7.
- Produces: nothing.

- [ ] **Step 1: Rebuild and bring the stack up**

Run: `cd build && docker compose build && docker compose up -d`
Expected: all three services healthy.

- [ ] **Step 2: Run the full Python suite**

Run: `cd build/web && python -m pytest tests/ -v`
Expected: PASS, no skips.

- [ ] **Step 3: Run the live integration smoke test through the proxy**

Run: `cd build/web && BASE_URL=https://localhost python3 tests/integration_smoke.py`
Expected: PASS. This is the load-bearing check that full-width Unicode LDAP payloads and the branding-SSRF-to-SSTI hop still work through nginx after the template changes.

- [ ] **Step 4: Run the full chain replay**

Run: `cd build/exploit && ./full-chain-replay.sh`
Expected: every phase PASS. Phase 2 in particular must still report "rabbit hole contains no real AD account names" — it selects only `username` from `legacy_auth.users`, which Task 2 left untouched.

- [ ] **Step 5: Confirm the roster from the attacker's side of the tunnel**

Run, over the established pivot: `bloodhound-python -u svc_ldap -p '<svc_ldap password>' -d donerup.htb -c All -dc dc01.donerup.htb`
Expected: the collection returns the roster and groups, and the `svc_ldap -> svc_backup` `GenericWrite` edge is still present and still the only interesting edge in the graph.

- [ ] **Step 6: Sanity-check login latency against the larger directory**

Run: `curl -sk -o /dev/null -w "%{time_total}\n" -X POST https://localhost/login -d 'username=jdoe&password=SogukDonerAyran7'`
Expected: comparable to the pre-roster timing. Every login is a subtree search; 25 accounts should be immeasurable, but this closes the spec's open question rather than assuming it.

- [ ] **Step 7: Commit any fixes**

If Steps 1-6 all pass, there is nothing to commit and the plan is complete. If any step failed, fix the cause, re-run that step and every later one, then commit:

```bash
git add -A
git commit -m "fix: <what the live sweep turned up>"
```

---

## Self-review notes

- **Spec coverage.** Canon → Tasks 1-3 content; Layer 1 (AD) → Task 7; Layer 2 (web) → Tasks 4-6; Layer 3 (container) → Task 3; Layer 4 (legacy DB) → Task 2; Consistency → Tasks 1-3, 5; every "Risks and open questions" item → Task 8, except the CSS-effort risk, which is addressed by Tasks 4-6 reusing the existing `.panel-title`/`.portal-bar` idiom rather than introducing a second visual language.
- **One spec risk closed early.** The spec listed "`full-chain-replay.sh` has not been read for content assertions" as its one non-static risk. It has now been read: line 92 runs `SELECT username FROM legacy_auth.users` and nothing else, so Task 2 cannot affect it. Task 8 Step 4 still runs the replay end to end.
- **Type consistency.** `load_employees` / `load_stores` / `REPO` / `STORE_CODE_RE` / `EMP_ID_RE` are defined once in Task 1 and used unchanged in Tasks 2, 3 and 5. CSV column names (`sam`, `display_name`, `employee_id`, `manager_sam`, `groups`, `enabled`) are identical in the Python tests and the PowerShell `Import-Csv` consumer.

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


TEMPLATES_DIR = REPO / "build" / "web" / "app" / "templates"


def test_templates_reference_only_known_store_codes():
    """Read as utf-8, not ascii: the spec's ASCII rule governs the content
    this layer *adds* (directory attributes, CSV, SQL, documents). Template
    markup predates it and login.html's <title> already carries a literal
    em dash."""
    known = {r["code"] for r in load_stores()}
    for path in sorted(TEMPLATES_DIR.glob("*.html")):
        for code in set(STORE_CODE_RE.findall(path.read_text(encoding="utf-8"))):
            assert code in known, path.name


def test_stylesheet_never_uses_translucent_white_text():
    """The portal renders on `body { background: var(--white) }`, and its
    secondary text uses var(--grey). Translucent white is invisible there;
    it slipped in twice while building the dashboard and was caught by
    review, not by a test."""
    css = (REPO / "build" / "web" / "app" / "static" / "css" / "donerup.css").read_text(
        encoding="utf-8"
    )
    assert "rgba(255, 255, 255" not in css
    assert "rgba(255,255,255" not in css

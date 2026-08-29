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

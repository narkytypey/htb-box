import pytest
from ldap3 import Server, Connection, MOCK_SYNC

from app.ldap_auth import authenticate, is_privileged
from app.sanitize import sanitize


@pytest.fixture
def ldap_conn():
    server = Server("donerup-mock")
    conn = Connection(
        server,
        user="cn=svc_ldap,dc=donerup,dc=htb",
        password="mock-password",
        client_strategy=MOCK_SYNC,
    )
    # administrator: privileged, excluded from the legacy migration -> no 'info' at all
    conn.strategy.add_entry(
        "cn=administrator,ou=users,dc=donerup,dc=htb",
        {
            "sAMAccountName": "administrator",
            "objectClass": "user",
            "memberOf": "CN=Domain Admins,DC=donerup,DC=htb",
        },
    )
    # jdoe: regular migrated user, 'info' holds the legacy plaintext-equivalent value
    conn.strategy.add_entry(
        "cn=jdoe,ou=users,dc=donerup,dc=htb",
        {
            "sAMAccountName": "jdoe",
            "objectClass": "user",
            "info": "CorrectHorseBattery1",
        },
    )
    conn.bind()
    return conn


def test_wrong_username_is_rejected(ldap_conn):
    ok, _ = authenticate(ldap_conn, "nosuchuser", "whatever")
    assert ok is False


def test_correct_password_for_regular_user_succeeds(ldap_conn):
    ok, _ = authenticate(ldap_conn, "jdoe", "CorrectHorseBattery1")
    assert ok is True


def test_wrong_password_for_regular_user_fails(ldap_conn):
    ok, _ = authenticate(ldap_conn, "jdoe", "wrongpass")
    assert ok is False


def test_username_field_or_breakout_bypasses_admin_without_info(ldap_conn):
    username = sanitize("administrator）（|（sAMAccountName=administrator")
    password = sanitize("）")
    ok, member_of = authenticate(ldap_conn, username, password)
    assert ok is True
    assert is_privileged(member_of) is True


def test_or_breakout_generalizes_to_other_users_without_real_password(ldap_conn):
    username = sanitize("jdoe）（|（sAMAccountName=jdoe")
    password = sanitize("）")
    ok, _ = authenticate(ldap_conn, username, password)
    assert ok is True


def test_or_breakout_fails_if_inner_branch_is_false(ldap_conn):
    """Necessity check: the injected OR only works because its first branch
    is a true predicate. Swap it for a false one and the bypass must fail —
    proving the OR is load-bearing, not decorative."""
    username = sanitize("administrator）（|（sAMAccountName=nosuchuser")
    password = sanitize("）")
    ok, _ = authenticate(ldap_conn, username, password)
    assert ok is False


def test_password_only_wildcard_works_for_regular_user_but_not_admin(ldap_conn):
    """Side effect of the info-absent-for-privileged-accounts data model:
    a bare presence-wildcard on `info` still bypasses regular users, but
    never admin, since admin has no `info` attribute to match."""
    password = sanitize("＊")

    ok_jdoe, _ = authenticate(ldap_conn, "jdoe", password)
    assert ok_jdoe is True

    ok_admin, _ = authenticate(ldap_conn, "administrator", password)
    assert ok_admin is False

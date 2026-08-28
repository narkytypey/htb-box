import os

from ldap3 import Server, Connection, SYNC, MOCK_SYNC


def real_ldap_connection():
    """Bind against the real DC (Plan 3). Reads config at call time so it
    picks up env vars set after import (e.g. by tests or by docker-compose)."""
    server_host = os.environ.get("LDAP_SERVER_HOST", "dc01.donerup.htb")
    bind_dn = os.environ.get(
        "LDAP_BIND_DN", "CN=svc_ldap,OU=Service Accounts,DC=donerup,DC=htb"
    )
    bind_password = os.environ.get("LDAP_BIND_PASSWORD", "")

    server = Server(server_host)
    return Connection(
        server,
        user=bind_dn,
        password=bind_password,
        client_strategy=SYNC,
        auto_bind=True,
    )


def mock_ldap_connection():
    """In-memory LDAP backend for local dev/CI before the real DC (Plan 3)
    exists. Same fixture data used throughout design verification."""
    server = Server("donerup-mock")
    conn = Connection(
        server,
        user="cn=svc_ldap,dc=donerup,dc=htb",
        password="mock-password",
        client_strategy=MOCK_SYNC,
    )
    conn.strategy.add_entry(
        "cn=administrator,ou=users,dc=donerup,dc=htb",
        {
            "sAMAccountName": "administrator",
            "objectClass": "user",
            "memberOf": "CN=Domain Admins,DC=donerup,DC=htb",
        },
    )
    conn.strategy.add_entry(
        "cn=jdoe,ou=users,dc=donerup,dc=htb",
        {
            "sAMAccountName": "jdoe",
            "objectClass": "user",
            "info": "SogukDonerAyran7",
        },
    )
    conn.bind()
    return conn


def get_ldap_connection_factory():
    """LDAP_MODE=mock -> in-memory backend (Plan 1 default). Anything else
    (including unset) -> real DC bind (Plan 3 deployment)."""
    if os.environ.get("LDAP_MODE", "real") == "mock":
        return mock_ldap_connection
    return real_ldap_connection

import os

from app import ldap_connection


class FakeServer:
    def __init__(self, host):
        self.host = host


class FakeConnection:
    def __init__(self, server, **kwargs):
        self.server = server
        self.kwargs = kwargs


def test_real_ldap_connection_uses_env_config(monkeypatch):
    monkeypatch.setenv("LDAP_SERVER_HOST", "dc01.donerup.htb")
    monkeypatch.setenv("LDAP_BIND_DN", "CN=svc_ldap,OU=Service Accounts,DC=donerup,DC=htb")
    monkeypatch.setenv("LDAP_BIND_PASSWORD", "test-password")
    monkeypatch.setattr(ldap_connection, "Server", FakeServer)
    monkeypatch.setattr(ldap_connection, "Connection", FakeConnection)

    conn = ldap_connection.real_ldap_connection()

    assert conn.server.host == "dc01.donerup.htb"
    assert conn.kwargs["user"] == "CN=svc_ldap,OU=Service Accounts,DC=donerup,DC=htb"
    assert conn.kwargs["password"] == "test-password"
    assert conn.kwargs["auto_bind"] is True


def test_mock_ldap_connection_has_administrator_and_jdoe():
    conn = ldap_connection.mock_ldap_connection()
    conn.search("dc=donerup,dc=htb", "(sAMAccountName=administrator)", attributes=["memberOf"])
    assert len(conn.entries) == 1


def test_get_ldap_connection_factory_defaults_to_real(monkeypatch):
    monkeypatch.delenv("LDAP_MODE", raising=False)
    assert ldap_connection.get_ldap_connection_factory() is ldap_connection.real_ldap_connection


def test_get_ldap_connection_factory_returns_mock_when_configured(monkeypatch):
    monkeypatch.setenv("LDAP_MODE", "mock")
    assert ldap_connection.get_ldap_connection_factory() is ldap_connection.mock_ldap_connection

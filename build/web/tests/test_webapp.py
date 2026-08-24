from app.ldap_connection import mock_ldap_connection
from app.webapp import create_app


def make_app():
    return create_app(ldap_connection_factory=mock_ldap_connection)


def test_wrong_login_is_rejected():
    client = make_app().test_client()
    resp = client.post("/login", data={"username": "administrator", "password": "wrong"})
    assert resp.status_code == 401


def test_legit_regular_user_login_succeeds():
    client = make_app().test_client()
    resp = client.post(
        "/login",
        data={"username": "jdoe", "password": "CorrectHorseBattery1"},
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Welcome, jdoe" in resp.data


def test_verified_or_breakout_authenticates_as_administrator_over_http():
    client = make_app().test_client()
    resp = client.post(
        "/login",
        data={
            "username": "administrator）（|（sAMAccountName=administrator",
            "password": "）",
        },
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Welcome, administrator" in resp.data

from app.ldap_connection import mock_ldap_connection
from app.webapp import create_app


def make_app():
    return create_app(ldap_connection_factory=mock_ldap_connection)


def test_login_page_seeds_the_ldap_theme():
    """Spec S3: the login page must reference the corporate LDAP directory,
    so step 1 is derivable by enumeration rather than guessed (spec S1,
    "Guessing yok"). It must stay a *theme* hint only -- naming the
    vulnerable field or the bypass would collapse the Insane difficulty
    rating S4.1 depends on."""
    client = make_app().test_client()
    body = client.get("/login").data.lower()
    assert b"ldap" in body
    for giveaway in (b"inject", b"fullwidth", b"full-width", b"bypass", b"sanitiz"):
        assert giveaway not in body


def test_wrong_login_is_rejected():
    client = make_app().test_client()
    resp = client.post("/login", data={"username": "administrator", "password": "wrong"})
    assert resp.status_code == 401


def test_legit_regular_user_login_succeeds():
    client = make_app().test_client()
    resp = client.post(
        "/login",
        data={"username": "jdoe", "password": "SogukDonerAyran7"},
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


def test_dashboard_never_echoes_the_injection_payload():
    """The bypass must land the player on a clean dashboard. Echoing the
    payload back breaks the corporate-portal illusion at the exact moment
    of foothold, and reflects attacker input into HTML — a sink that is no
    part of the designed chain (spec S4.1 / S4.2)."""
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
    assert resp.data.rstrip().endswith(b"Welcome, administrator")
    for fragment in (b")(|(", b"sAMAccountName", b"\xef\xbc\x89", b"\xef\xbc\x88"):
        assert fragment not in resp.data


def test_dashboard_escapes_html_metacharacters_in_the_account_name():
    """Defence in depth: even if a directory ever hands back an account
    name containing markup, it must be escaped rather than rendered."""
    class _Entry:
        sAMAccountName = type("V", (), {"value": "<script>x</script>"})()
        memberOf = ["CN=Domain Admins,DC=donerup,DC=htb"]

        def __contains__(self, item):
            return item in ("sAMAccountName", "memberOf")

    class _Conn:
        entries = [_Entry()]

        def search(self, *a, **kw):
            return True

    client = create_app(ldap_connection_factory=lambda: _Conn()).test_client()
    resp = client.post(
        "/login", data={"username": "x", "password": "y"}, follow_redirects=True
    )
    assert b"<script>" not in resp.data
    assert b"&lt;script&gt;" in resp.data


def _login_as_administrator(client):
    return client.post(
        "/login",
        data={
            "username": "administrator）（|（sAMAccountName=administrator",
            "password": "）",
        },
    )


def test_admin_panel_blocks_naive_ssti_payload():
    client = make_app().test_client()
    _login_as_administrator(client)
    resp = client.post("/admin/report-template", data={"template": "{{ ''.__class__ }}"})
    assert resp.status_code == 400


def test_admin_panel_renders_verified_ssti_bypass():
    client = make_app().test_client()
    _login_as_administrator(client)
    resp = client.post(
        "/admin/report-template",
        data={"template": "{{''['_'~'_cla'~'ss_'~'_']}}"},
    )
    assert resp.status_code == 200
    assert b"class 'str'" in resp.data


def test_admin_panel_blocks_quoted_close_brace_regex_bypass():
    """A prior blacklist implementation extracted {{ ... }} with a plain
    non-greedy regex, which stopped at the first literal '}}' even when it
    appeared inside a quoted string -- so {{("}}"~"")...}} was scanned as
    the harmless fragment {{("}} and the real payload after it skipped the
    blacklist entirely. This must be blocked like any other banned-token
    payload, not treated as a second sanctioned bypass."""
    client = make_app().test_client()
    _login_as_administrator(client)
    resp = client.post(
        "/admin/report-template",
        data={"template": '{{("}}"~"").__class__.__mro__[1].__subclasses__()}}'},
    )
    assert resp.status_code == 400


def test_admin_panel_renders_realistic_prose_template():
    client = make_app().test_client()
    _login_as_administrator(client)
    resp = client.post(
        "/admin/report-template",
        data={"template": "Hello {{name}}, your report is ready."},
    )
    assert resp.status_code == 200


def test_regular_user_cannot_reach_admin_panel():
    client = make_app().test_client()
    client.post(
        "/login",
        data={"username": "jdoe", "password": "SogukDonerAyran7"},
    )
    resp = client.get("/admin/report-template")
    assert resp.status_code == 403

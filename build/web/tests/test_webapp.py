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


def test_report_template_rejects_non_loopback_requests_even_as_administrator():
    """The old gate was session["is_privileged"]; the new one is loopback-
    only (spec Approach A). An app-admin session must no longer be
    sufficient on its own -- proving that is the point of this test."""
    client = make_app().test_client()
    _login_as_administrator(client)
    resp = client.get(
        "/admin/report-template",
        environ_overrides={"REMOTE_ADDR": "203.0.113.5"},
    )
    assert resp.status_code == 403


def test_report_template_accepts_loopback_requests_with_no_session_at_all():
    """The real story: an internal batch job calls this locally and was
    never given a session. remote_addr == 127.0.0.1 is the Flask test
    client's default, so no override is needed here."""
    client = make_app().test_client()
    resp = client.get("/admin/report-template")
    assert resp.status_code == 200


def test_report_template_ignores_a_forged_x_forwarded_for_header():
    """The loopback gate is the single load-bearing security property of
    this whole plan (spec Approach A) -- it must key off the real TCP peer
    address only. A forged X-Forwarded-For/X-Real-IP claiming 127.0.0.1
    must not grant access to a request that actually arrived from
    elsewhere."""
    client = make_app().test_client()
    resp = client.get(
        "/admin/report-template",
        headers={"X-Forwarded-For": "127.0.0.1", "X-Real-IP": "127.0.0.1"},
        environ_overrides={"REMOTE_ADDR": "203.0.113.5"},
    )
    assert resp.status_code == 403


def test_report_template_renders_a_query_string_payload_from_loopback():
    """This is the actual SSRF exploitation primitive: a GET with the
    payload in the query string, which is what a server-side
    requests.get() call (Task 1/2's branding fetcher) forges."""
    client = make_app().test_client()
    resp = client.get(
        "/admin/report-template",
        query_string={"template": "{{''['_'~'_cla'~'ss_'~'_']}}"},
    )
    assert resp.status_code == 200
    assert b"class 'str'" in resp.data


def test_report_template_blocks_a_blacklisted_query_string_payload():
    client = make_app().test_client()
    resp = client.get(
        "/admin/report-template",
        query_string={"template": "{{ ''.__class__ }}"},
    )
    assert resp.status_code == 400


class _FakeImageResponse:
    def __init__(self):
        self.status_code = 200
        self.headers = {"Content-Type": "image/png"}

    def iter_content(self, chunk_size):
        yield b"\x89PNG"

    def close(self):
        pass


class _FakeNonImageResponse:
    def __init__(self, status_code, body):
        self.status_code = status_code
        self.headers = {"Content-Type": "text/html"}
        self._body = body

    def iter_content(self, chunk_size):
        yield self._body

    def close(self):
        pass


def _make_app_with_http_get(http_get):
    return create_app(ldap_connection_factory=mock_ldap_connection, http_get=http_get)


def test_branding_requires_an_admin_session():
    client = _make_app_with_http_get(lambda *a, **kw: _FakeImageResponse()).test_client()
    resp = client.post("/admin/branding", data={"logo_url": "http://cdn.example.com/logo.png"})
    assert resp.status_code == 403


def test_branding_rejects_an_authenticated_non_admin_user():
    """/admin/branding is still session-gated (unlike /admin/report-template,
    which moved to a loopback-only gate). An authenticated but
    non-privileged session must be rejected, not just an anonymous one."""
    client = _make_app_with_http_get(lambda *a, **kw: _FakeImageResponse()).test_client()
    client.post("/login", data={"username": "jdoe", "password": "SogukDonerAyran7"})
    resp = client.post("/admin/branding", data={"logo_url": "http://cdn.example.com/logo.png"})
    assert resp.status_code == 403


def test_branding_accepts_a_real_looking_image():
    client = _make_app_with_http_get(lambda *a, **kw: _FakeImageResponse()).test_client()
    _login_as_administrator(client)
    resp = client.post("/admin/branding", data={"logo_url": "http://cdn.example.com/logo.png"})
    assert resp.status_code == 200


def test_branding_leaks_a_snippet_of_a_non_image_response():
    http_get = lambda *a, **kw: _FakeNonImageResponse(200, b"internal-only-data-12345")
    client = _make_app_with_http_get(http_get).test_client()
    _login_as_administrator(client)
    resp = client.post("/admin/branding", data={"logo_url": "http://127.0.0.1:5000/anything"})
    assert resp.status_code == 400
    assert b"internal-only-data-12345" in resp.data


def test_branding_form_page_renders_for_an_admin():
    client = _make_app_with_http_get(lambda *a, **kw: _FakeImageResponse()).test_client()
    _login_as_administrator(client)
    resp = client.get("/admin/branding")
    assert resp.status_code == 200
    assert b"logo_url" in resp.data

